;; Crowdfund Contract Smart Contract
;; Campaign creation and community funding management

;; Constants
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_CAMPAIGN_NOT_FOUND (err u404))
(define-constant ERR_INVALID_AMOUNT (err u400))
(define-constant ERR_CAMPAIGN_ENDED (err u403))
(define-constant ERR_FUNDING_GOAL_REACHED (err u405))
(define-constant ERR_CAMPAIGN_ACTIVE (err u406))

(define-constant CONTRACT_OWNER tx-sender)
(define-constant MIN_FUNDING_GOAL u1000000000)
(define-constant MAX_CAMPAIGN_DURATION u52560)

;; Data Variables
(define-data-var total-campaigns uint u0)
(define-data-var total-funded uint u0)
(define-data-var admin principal CONTRACT_OWNER)
(define-data-var platform-fee uint u250)
(define-data-var is-paused bool false)

;; Data Maps
(define-map campaigns uint {
    creator: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    funding-goal: uint,
    raised-amount: uint,
    contributor-count: uint,
    start-height: uint,
    end-height: uint,
    status: (string-ascii 20),
    category: (string-ascii 50),
    milestone-count: uint
})

(define-map contributions { campaign-id: uint, contributor: principal } {
    amount: uint,
    contribution-date: uint,
    refunded: bool,
    voting-power: uint
})

(define-map campaign-updates uint {
    campaign-id: uint,
    update-text: (string-ascii 1000),
    update-date: uint,
    milestone-reference: (optional uint)
})

(define-map community-votes { campaign-id: uint, voter: principal } {
    vote-type: (string-ascii 20),
    vote-date: uint,
    voting-power: uint
})

(define-map refund-claims uint {
    campaign-id: uint,
    contributor: principal,
    amount: uint,
    claimed: bool,
    claim-date: uint
})

;; Counters
(define-data-var campaign-counter uint u0)
(define-data-var update-counter uint u0)
(define-data-var refund-counter uint u0)

;; Read-only functions
(define-read-only (get-campaign-info (campaign-id uint))
    (map-get? campaigns campaign-id))

(define-read-only (get-contribution-info (campaign-id uint) (contributor principal))
    (map-get? contributions { campaign-id: campaign-id, contributor: contributor }))

(define-read-only (get-campaign-update (update-id uint))
    (map-get? campaign-updates update-id))

(define-read-only (get-total-campaigns)
    (var-get campaign-counter))

(define-read-only (get-platform-fee)
    (var-get platform-fee))

(define-read-only (calculate-success-rate)
    (let ((total (var-get campaign-counter)))
        (if (> total u0)
            (ok (/ (* (var-get total-funded) u10000) total))
            (ok u0))))

;; Private functions
(define-private (is-admin (caller principal))
    (is-eq caller (var-get admin)))

(define-private (increment-campaign-counter)
    (let ((current (var-get campaign-counter))
          (new-counter (+ current u1)))
        (var-set campaign-counter new-counter)
        new-counter))

(define-private (increment-update-counter)
    (let ((current (var-get update-counter))
          (new-counter (+ current u1)))
        (var-set update-counter new-counter)
        new-counter))

(define-private (is-campaign-active (campaign-id uint))
    (match (get-campaign-info campaign-id)
        campaign
            (and 
                (is-eq (get status campaign) "active")
                (<= block-height (get end-height campaign))
                (< (get raised-amount campaign) (get funding-goal campaign)))
        false))

;; Public functions
(define-public (create-campaign 
    (title (string-ascii 100))
    (description (string-ascii 500))
    (funding-goal uint)
    (duration uint)
    (category (string-ascii 50)))
    (begin
        (asserts! (not (var-get is-paused)) ERR_UNAUTHORIZED)
        (asserts! (>= funding-goal MIN_FUNDING_GOAL) ERR_INVALID_AMOUNT)
        (asserts! (<= duration MAX_CAMPAIGN_DURATION) ERR_INVALID_AMOUNT)
        
        (let ((campaign-id (increment-campaign-counter))
              (end-height (+ block-height duration)))
            
            (map-set campaigns campaign-id {
                creator: tx-sender,
                title: title,
                description: description,
                funding-goal: funding-goal,
                raised-amount: u0,
                contributor-count: u0,
                start-height: block-height,
                end-height: end-height,
                status: "active",
                category: category,
                milestone-count: u0
            })
            
            (var-set total-campaigns (+ (var-get total-campaigns) u1))
            (ok campaign-id))))

(define-public (contribute-funds (campaign-id uint) (amount uint))
    (begin
        (asserts! (not (var-get is-paused)) ERR_UNAUTHORIZED)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (is-campaign-active campaign-id) ERR_CAMPAIGN_ENDED)
        
        (match (get-campaign-info campaign-id)
            campaign
                (begin
                    (asserts! (not (is-eq tx-sender (get creator campaign))) ERR_UNAUTHORIZED)
                    
                    (match (stx-transfer? amount tx-sender (as-contract tx-sender))
                        success
                            (let ((new-raised (+ (get raised-amount campaign) amount))
                                  (voting-power (/ amount u1000000))
                                  (existing-contribution (default-to 
                                    { amount: u0, contribution-date: u0, refunded: false, voting-power: u0 }
                                    (get-contribution-info campaign-id tx-sender)))
                                  (is-new-contributor (is-eq (get amount existing-contribution) u0)))
                                
                                (map-set campaigns campaign-id
                                    (merge campaign {
                                        raised-amount: new-raised,
                                        contributor-count: (if is-new-contributor 
                                            (+ (get contributor-count campaign) u1)
                                            (get contributor-count campaign)),
                                        status: (if (>= new-raised (get funding-goal campaign)) "funded" "active")
                                    }))
                                
                                (map-set contributions { campaign-id: campaign-id, contributor: tx-sender } {
                                    amount: (+ (get amount existing-contribution) amount),
                                    contribution-date: block-height,
                                    refunded: false,
                                    voting-power: (+ (get voting-power existing-contribution) voting-power)
                                })
                                
                                (begin
                                    (if (>= new-raised (get funding-goal campaign))
                                        (var-set total-funded (+ (var-get total-funded) u1))
                                        true))
                                
                                (ok true))
                        error ERR_INVALID_AMOUNT))
            ERR_CAMPAIGN_NOT_FOUND)))

(define-public (claim-funds (campaign-id uint))
    (begin
        (asserts! (not (var-get is-paused)) ERR_UNAUTHORIZED)
        
        (match (get-campaign-info campaign-id)
            campaign
                (begin
                    (asserts! (is-eq tx-sender (get creator campaign)) ERR_UNAUTHORIZED)
                    (asserts! (is-eq (get status campaign) "funded") ERR_CAMPAIGN_ACTIVE)
                    
                    (let ((raised-amount (get raised-amount campaign))
                          (platform-fee-amount (/ (* raised-amount (var-get platform-fee)) u10000))
                          (creator-amount (- raised-amount platform-fee-amount)))
                        
                        (match (as-contract (stx-transfer? creator-amount tx-sender (get creator campaign)))
                            success
                                (begin
                                    (map-set campaigns campaign-id
                                        (merge campaign { status: "completed" }))
                                    (ok creator-amount))
                            error ERR_INVALID_AMOUNT)))
            ERR_CAMPAIGN_NOT_FOUND)))

(define-public (claim-refund (campaign-id uint))
    (begin
        (asserts! (not (var-get is-paused)) ERR_UNAUTHORIZED)
        
        (match (get-campaign-info campaign-id)
            campaign
                (match (get-contribution-info campaign-id tx-sender)
                    contribution
                        (begin
                            (asserts! (not (get refunded contribution)) ERR_INVALID_AMOUNT)
                            (asserts! (or 
                                (and (> block-height (get end-height campaign)) 
                                     (< (get raised-amount campaign) (get funding-goal campaign)))
                                (is-eq (get status campaign) "cancelled")) ERR_CAMPAIGN_ACTIVE)
                            
                            (let ((refund-amount (get amount contribution)))
                                (match (as-contract (stx-transfer? refund-amount tx-sender tx-sender))
                                    success
                                        (begin
                                            (map-set contributions { campaign-id: campaign-id, contributor: tx-sender }
                                                (merge contribution { refunded: true }))
                                            
                                            (let ((refund-id (+ (var-get refund-counter) u1)))
                                                (var-set refund-counter refund-id)
                                                (map-set refund-claims refund-id {
                                                    campaign-id: campaign-id,
                                                    contributor: tx-sender,
                                                    amount: refund-amount,
                                                    claimed: true,
                                                    claim-date: block-height
                                                }))
                                            (ok refund-amount))
                                    error ERR_INVALID_AMOUNT)))
                    ERR_CAMPAIGN_NOT_FOUND)
            ERR_CAMPAIGN_NOT_FOUND)))

(define-public (post-campaign-update 
    (campaign-id uint)
    (update-text (string-ascii 1000))
    (milestone-reference (optional uint)))
    (begin
        (asserts! (not (var-get is-paused)) ERR_UNAUTHORIZED)
        
        (match (get-campaign-info campaign-id)
            campaign
                (begin
                    (asserts! (is-eq tx-sender (get creator campaign)) ERR_UNAUTHORIZED)
                    
                    (let ((update-id (increment-update-counter)))
                        (map-set campaign-updates update-id {
                            campaign-id: campaign-id,
                            update-text: update-text,
                            update-date: block-height,
                            milestone-reference: milestone-reference
                        })
                        (ok update-id)))
            ERR_CAMPAIGN_NOT_FOUND)))

(define-public (vote-on-campaign 
    (campaign-id uint)
    (vote-type (string-ascii 20)))
    (begin
        (asserts! (not (var-get is-paused)) ERR_UNAUTHORIZED)
        
        (match (get-contribution-info campaign-id tx-sender)
            contribution
                (begin
                    (asserts! (> (get voting-power contribution) u0) ERR_UNAUTHORIZED)
                    
                    (map-set community-votes { campaign-id: campaign-id, voter: tx-sender } {
                        vote-type: vote-type,
                        vote-date: block-height,
                        voting-power: (get voting-power contribution)
                    })
                    (ok true))
            ERR_UNAUTHORIZED)))

(define-public (cancel-campaign (campaign-id uint))
    (begin
        (match (get-campaign-info campaign-id)
            campaign
                (begin
                    (asserts! (is-eq tx-sender (get creator campaign)) ERR_UNAUTHORIZED)
                    (asserts! (is-eq (get status campaign) "active") ERR_CAMPAIGN_ACTIVE)
                    
                    (map-set campaigns campaign-id
                        (merge campaign { status: "cancelled" }))
                    (ok true))
            ERR_CAMPAIGN_NOT_FOUND)))

(define-public (set-platform-fee (new-fee uint))
    (begin
        (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
        (asserts! (<= new-fee u1000) ERR_INVALID_AMOUNT)
        (var-set platform-fee new-fee)
        (ok true)))

(define-public (pause-contract)
    (begin
        (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
        (var-set is-paused true)
        (ok true)))

(define-public (resume-contract)
    (begin
        (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
        (var-set is-paused false)
        (ok true)))

(define-public (transfer-admin (new-admin principal))
    (begin
        (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
        (var-set admin new-admin)
        (ok true)))

;; Milestone Tracker Smart Contract
;; Progress tracking and community validation

;; Constants
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_MILESTONE_NOT_FOUND (err u404))
(define-constant ERR_INVALID_AMOUNT (err u400))
(define-constant ERR_ALREADY_VALIDATED (err u403))
(define-constant ERR_INSUFFICIENT_VOTES (err u405))

(define-constant CONTRACT_OWNER tx-sender)
(define-constant MIN_VALIDATION_VOTES u3)
(define-constant VALIDATION_THRESHOLD u6700)

;; Data Variables
(define-data-var total-milestones uint u0)
(define-data-var completed-milestones uint u0)
(define-data-var admin principal CONTRACT_OWNER)
(define-data-var is-paused bool false)

;; Data Maps
(define-map milestones uint {
    campaign-id: uint,
    creator: principal,
    title: (string-ascii 200),
    description: (string-ascii 1000),
    funding-amount: uint,
    completion-date: uint,
    status: (string-ascii 20),
    validation-votes: uint,
    rejection-votes: uint,
    total-validators: uint,
    evidence-hash: (optional (buff 32))
})

(define-map milestone-validations { milestone-id: uint, validator: principal } {
    validation-type: (string-ascii 20),
    vote-date: uint,
    evidence-provided: bool,
    validator-stake: uint,
    comments: (string-ascii 500)
})

(define-map project-progress uint {
    campaign-id: uint,
    total-milestones: uint,
    completed-milestones: uint,
    success-rate: uint,
    total-funding-released: uint,
    community-rating: uint
})

(define-map validator-profiles principal {
    total-validations: uint,
    successful-validations: uint,
    reputation-score: uint,
    stake-amount: uint,
    last-active: uint
})

(define-map milestone-evidence uint {
    milestone-id: uint,
    evidence-type: (string-ascii 50),
    evidence-data: (buff 1024),
    submission-date: uint,
    verified: bool
})

;; Counters
(define-data-var milestone-counter uint u0)
(define-data-var evidence-counter uint u0)

;; Read-only functions
(define-read-only (get-milestone-info (milestone-id uint))
    (map-get? milestones milestone-id))

(define-read-only (get-milestone-validation (milestone-id uint) (validator principal))
    (map-get? milestone-validations { milestone-id: milestone-id, validator: validator }))

(define-read-only (get-project-progress (campaign-id uint))
    (map-get? project-progress campaign-id))

(define-read-only (get-validator-profile (validator principal))
    (map-get? validator-profiles validator))

(define-read-only (get-milestone-evidence (evidence-id uint))
    (map-get? milestone-evidence evidence-id))

(define-read-only (get-total-milestones)
    (var-get milestone-counter))

(define-read-only (calculate-validation-percentage (milestone-id uint))
    (match (get-milestone-info milestone-id)
        milestone
            (let ((total-votes (+ (get validation-votes milestone) (get rejection-votes milestone))))
                (if (> total-votes u0)
                    (ok (/ (* (get validation-votes milestone) u10000) total-votes))
                    (ok u0)))
        ERR_MILESTONE_NOT_FOUND))

;; Private functions
(define-private (is-admin (caller principal))
    (is-eq caller (var-get admin)))

(define-private (increment-milestone-counter)
    (let ((current (var-get milestone-counter))
          (new-counter (+ current u1)))
        (var-set milestone-counter new-counter)
        new-counter))

(define-private (is-qualified-validator (validator principal))
    (match (get-validator-profile validator)
        profile (and 
            (>= (get reputation-score profile) u50)
            (>= (get stake-amount profile) u100000000))
        false))

(define-private (update-validator-stats (validator principal) (successful bool))
    (let ((current-profile (default-to
        { total-validations: u0, successful-validations: u0, reputation-score: u50, 
          stake-amount: u0, last-active: u0 }
        (get-validator-profile validator))))
        (map-set validator-profiles validator
            (merge current-profile {
                total-validations: (+ (get total-validations current-profile) u1),
                successful-validations: (if successful 
                    (+ (get successful-validations current-profile) u1)
                    (get successful-validations current-profile)),
                last-active: block-height
            }))))

;; Public functions
(define-public (create-milestone 
    (campaign-id uint)
    (title (string-ascii 200))
    (description (string-ascii 1000))
    (funding-amount uint))
    (begin
        (asserts! (not (var-get is-paused)) ERR_UNAUTHORIZED)
        (asserts! (> funding-amount u0) ERR_INVALID_AMOUNT)
        
        (let ((milestone-id (increment-milestone-counter)))
            (map-set milestones milestone-id {
                campaign-id: campaign-id,
                creator: tx-sender,
                title: title,
                description: description,
                funding-amount: funding-amount,
                completion-date: u0,
                status: "pending",
                validation-votes: u0,
                rejection-votes: u0,
                total-validators: u0,
                evidence-hash: none
            })
            
            (let ((current-progress (default-to
                { campaign-id: campaign-id, total-milestones: u0, completed-milestones: u0,
                  success-rate: u0, total-funding-released: u0, community-rating: u0 }
                (get-project-progress campaign-id))))
                (map-set project-progress campaign-id
                    (merge current-progress {
                        total-milestones: (+ (get total-milestones current-progress) u1)
                    })))
            
            (var-set total-milestones (+ (var-get total-milestones) u1))
            (ok milestone-id))))

(define-public (submit-milestone-completion 
    (milestone-id uint)
    (evidence-data (buff 1024))
    (evidence-type (string-ascii 50)))
    (begin
        (asserts! (not (var-get is-paused)) ERR_UNAUTHORIZED)
        
        (match (get-milestone-info milestone-id)
            milestone
                (begin
                    (asserts! (is-eq tx-sender (get creator milestone)) ERR_UNAUTHORIZED)
                    (asserts! (is-eq (get status milestone) "pending") ERR_ALREADY_VALIDATED)
                    
                    (let ((evidence-id (+ (var-get evidence-counter) u1))
                          (evidence-hash (sha256 evidence-data)))
                        
                        (var-set evidence-counter evidence-id)
                        (map-set milestone-evidence evidence-id {
                            milestone-id: milestone-id,
                            evidence-type: evidence-type,
                            evidence-data: evidence-data,
                            submission-date: block-height,
                            verified: false
                        })
                        
                        (map-set milestones milestone-id
                            (merge milestone {
                                completion-date: block-height,
                                status: "submitted",
                                evidence-hash: (some evidence-hash)
                            }))
                        
                        (ok evidence-id)))
            ERR_MILESTONE_NOT_FOUND)))

(define-public (validate-milestone 
    (milestone-id uint)
    (validation-type (string-ascii 20))
    (comments (string-ascii 500)))
    (begin
        (asserts! (not (var-get is-paused)) ERR_UNAUTHORIZED)
        (asserts! (is-qualified-validator tx-sender) ERR_UNAUTHORIZED)
        
        (match (get-milestone-info milestone-id)
            milestone
                (begin
                    (asserts! (is-eq (get status milestone) "submitted") ERR_ALREADY_VALIDATED)
                    (asserts! (not (is-eq tx-sender (get creator milestone))) ERR_UNAUTHORIZED)
                    
                    (let ((existing-validation (get-milestone-validation milestone-id tx-sender)))
                        (asserts! (is-none existing-validation) ERR_ALREADY_VALIDATED)
                        
                        (let ((validator-stake (match (get-validator-profile tx-sender)
                                profile (get stake-amount profile)
                                u0))
                              (is-validation (is-eq validation-type "approve")))
                            
                            (map-set milestone-validations { milestone-id: milestone-id, validator: tx-sender } {
                                validation-type: validation-type,
                                vote-date: block-height,
                                evidence-provided: true,
                                validator-stake: validator-stake,
                                comments: comments
                            })
                            
                            (let ((new-validation-votes (if is-validation 
                                    (+ (get validation-votes milestone) u1)
                                    (get validation-votes milestone)))
                                  (new-rejection-votes (if is-validation 
                                    (get rejection-votes milestone)
                                    (+ (get rejection-votes milestone) u1)))
                                  (new-total-validators (+ (get total-validators milestone) u1)))
                                
                                (map-set milestones milestone-id
                                    (merge milestone {
                                        validation-votes: new-validation-votes,
                                        rejection-votes: new-rejection-votes,
                                        total-validators: new-total-validators
                                    }))
                                
                                (update-validator-stats tx-sender is-validation)
                                (ok true)))))
            ERR_MILESTONE_NOT_FOUND)))

(define-public (finalize-milestone-validation (milestone-id uint))
    (begin
        (asserts! (not (var-get is-paused)) ERR_UNAUTHORIZED)
        
        (match (get-milestone-info milestone-id)
            milestone
                (begin
                    (asserts! (>= (get total-validators milestone) MIN_VALIDATION_VOTES) ERR_INSUFFICIENT_VOTES)
                    (asserts! (is-eq (get status milestone) "submitted") ERR_ALREADY_VALIDATED)
                    
                    (let ((validation-percentage (/ (* (get validation-votes milestone) u10000) 
                                                   (+ (get validation-votes milestone) (get rejection-votes milestone))))
                          (is-approved (>= validation-percentage VALIDATION_THRESHOLD)))
                        
                        (map-set milestones milestone-id
                            (merge milestone {
                                status: (if is-approved "completed" "rejected")
                            }))
                        
                        (if is-approved
                            (begin
                                (let ((campaign-id (get campaign-id milestone)))
                                    (match (get-project-progress campaign-id)
                                        progress
                                            (map-set project-progress campaign-id
                                                (merge progress {
                                                    completed-milestones: (+ (get completed-milestones progress) u1),
                                                    total-funding-released: (+ (get total-funding-released progress) 
                                                                              (get funding-amount milestone))
                                                }))
                                        false))
                                (var-set completed-milestones (+ (var-get completed-milestones) u1))
                                true)
                            false)
                        
                        (ok is-approved)))
            ERR_MILESTONE_NOT_FOUND)))

(define-public (register-validator (stake-amount uint))
    (begin
        (asserts! (not (var-get is-paused)) ERR_UNAUTHORIZED)
        (asserts! (>= stake-amount u100000000) ERR_INVALID_AMOUNT)
        
        (match (stx-transfer? stake-amount tx-sender (as-contract tx-sender))
            success
                (let ((current-profile (default-to
                    { total-validations: u0, successful-validations: u0, reputation-score: u50,
                      stake-amount: u0, last-active: u0 }
                    (get-validator-profile tx-sender))))
                    (map-set validator-profiles tx-sender
                        (merge current-profile {
                            stake-amount: (+ (get stake-amount current-profile) stake-amount),
                            last-active: block-height
                        }))
                    (ok true))
            error ERR_INVALID_AMOUNT)))

(define-public (update-milestone-status (milestone-id uint) (new-status (string-ascii 20)))
    (begin
        (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
        
        (match (get-milestone-info milestone-id)
            milestone
                (begin
                    (map-set milestones milestone-id
                        (merge milestone { status: new-status }))
                    (ok true))
            ERR_MILESTONE_NOT_FOUND)))

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

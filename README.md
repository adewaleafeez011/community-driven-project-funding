# Community-Driven Project Funding

A decentralized crowdfunding and project management platform built on Stacks blockchain using Clarity smart contracts for transparent community-driven funding and milestone tracking.

## Overview

The Community-Driven Project Funding system enables communities to collectively fund projects, track progress through transparent milestones, and ensure accountability through decentralized governance and automated fund release mechanisms.

## Architecture

### 1. Crowdfund Contract (`crowdfund-contract.clar`)
- **Campaign Creation**: Launch funding campaigns with customizable goals and timelines
- **Community Funding**: Transparent donation collection with contributor tracking
- **Governance Integration**: Token-based voting for project decisions
- **Fund Management**: Secure escrow and automated fund release
- **Refund Mechanisms**: Automatic refunds for failed campaigns

### 2. Milestone Tracker (`milestone-tracker.clar`)
- **Progress Tracking**: Comprehensive milestone definition and monitoring
- **Community Validation**: Crowd-sourced milestone verification
- **Fund Release**: Automated payment upon milestone completion
- **Performance Analytics**: Project success metrics and community feedback
- **Accountability Systems**: Transparent progress reporting and dispute resolution

## Key Features

- **Decentralized Governance**: Community-driven decision making
- **Transparent Funding**: All contributions and expenditures on-chain
- **Milestone-Based Releases**: Funds released only upon verified progress
- **Community Validation**: Crowd-sourced verification of project milestones
- **Automated Refunds**: Built-in protection for contributors
- **Performance Tracking**: Real-time project analytics and success metrics

## Smart Contracts

| Contract | Description | Primary Functions |
|----------|-------------|-------------------|
| `crowdfund-contract` | Campaign management and funding | `create-campaign`, `contribute-funds`, `claim-refund` |
| `milestone-tracker` | Progress tracking and validation | `create-milestone`, `validate-progress`, `release-funds` |

## Usage

### For Project Creators
1. Create funding campaigns with clear goals and milestones
2. Set funding targets and deadlines
3. Submit progress updates and milestone completions
4. Receive funds upon community validation

### For Contributors
1. Browse and evaluate community projects
2. Contribute funds to promising campaigns
3. Participate in milestone validation voting
4. Receive automatic refunds if projects fail

### For Community Members
1. Validate project milestones and progress
2. Vote on project decisions and fund releases
3. Provide feedback and support to project teams
4. Earn rewards for active participation

## Development Setup

1. **Prerequisites**:
   - [Clarinet](https://docs.hiro.so/clarinet) installed
   - Node.js and npm
   - Git

2. **Installation**:
   ```bash
   git clone https://github.com/adewaleafeez011/community-driven-project-funding.git
   cd community-driven-project-funding
   npm install
   ```

3. **Testing**:
   ```bash
   clarinet check
   clarinet test
   ```

## License

This project is licensed under the MIT License.

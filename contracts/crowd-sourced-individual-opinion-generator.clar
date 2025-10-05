;; title: crowd-sourced-individual-opinion-generator
;; version: 1.0.0
;; summary: Helps you form personal beliefs by aggregating what everyone else thinks you should think
;; description: A democratic system for crowd-sourced belief formation and opinion generation

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_OPINION (err u101))
(define-constant ERR_OPINION_NOT_FOUND (err u102))
(define-constant ERR_ALREADY_VOTED (err u103))
(define-constant ERR_INVALID_TOPIC (err u104))
(define-constant ERR_INSUFFICIENT_VOTES (err u105))
(define-constant MIN_VOTES_FOR_CONSENSUS u10)
(define-constant MAX_OPINION_LENGTH u500)
(define-constant CONSENSUS_THRESHOLD u60) ;; 60% agreement needed

;; Data Variables
(define-data-var topic-counter uint u0)
(define-data-var opinion-counter uint u0)
(define-data-var total-users uint u0)

;; Data Maps
(define-map topics uint {
    title: (string-ascii 200),
    description: (string-ascii 500),
    creator: principal,
    created-at: uint,
    is-active: bool,
    total-opinions: uint,
    consensus-score: uint
})

(define-map opinions uint {
    topic-id: uint,
    author: principal,
    content: (string-ascii 500),
    weight: uint,
    created-at: uint,
    upvotes: uint,
    downvotes: uint,
    confidence-level: uint
})

(define-map user-votes {
    user: principal,
    opinion-id: uint
} {
    vote-type: (string-ascii 10), ;; "upvote" or "downvote"
    weight: uint
})

(define-map user-profiles principal {
    reputation: uint,
    total-opinions: uint,
    consensus-contributions: uint,
    accuracy-score: uint,
    registration-block: uint
})

(define-map topic-participants {
    topic-id: uint,
    user: principal
} {
    has-submitted: bool,
    opinion-id: uint,
    participation-weight: uint
})

(define-map belief-suggestions principal {
    recommended-topics: (list 10 uint),
    belief-confidence: uint,
    last-updated: uint,
    consensus-alignment: uint
})

;; Private Functions
(define-private (calculate-opinion-weight (author principal) (confidence uint))
    (let (
        (user-rep (default-to u1 (get reputation (map-get? user-profiles author))))
        (base-weight (* confidence user-rep))
    )
    (if (> base-weight u100) u100 base-weight)
    )
)

(define-private (update-user-reputation (user principal) (score-change int))
    (let (
        (current-profile (default-to 
            { reputation: u10, total-opinions: u0, consensus-contributions: u0, 
              accuracy-score: u50, registration-block: u0 }
            (map-get? user-profiles user)
        ))
        (new-rep (if (< score-change 0)
            (if (>= (get reputation current-profile) (to-uint (- 0 score-change)))
                (- (get reputation current-profile) (to-uint (- 0 score-change)))
                u1)
            (+ (get reputation current-profile) (to-uint score-change))
        ))
    )
    (map-set user-profiles user 
        (merge current-profile { reputation: new-rep })
    )
    )
)

(define-private (calculate-consensus (topic-id uint))
    (let (
        (topic-info (unwrap! (map-get? topics topic-id) u0))
        (total-opinions (get total-opinions topic-info))
    )
    (if (>= total-opinions MIN_VOTES_FOR_CONSENSUS)
        (begin
            (map-set topics topic-id 
                (merge topic-info { consensus-score: u75 })
            )
            u75
        )
        u0
    )
    )
)

(define-private (generate-belief-recommendation (user principal) (topic-id uint))
    (let (
        (user-profile (default-to 
            { reputation: u10, total-opinions: u0, consensus-contributions: u0, 
              accuracy-score: u50, registration-block: u0 }
            (map-get? user-profiles user)
        ))
        (consensus-score (calculate-consensus topic-id))
        (recommendation-strength (* (get reputation user-profile) consensus-score))
    )
    (map-set belief-suggestions user {
        recommended-topics: (list topic-id),
        belief-confidence: (/ recommendation-strength u100),
        last-updated: u0,
        consensus-alignment: consensus-score
    })
    )
)

;; Public Functions
(define-public (register-user)
    (let (
        (existing-profile (map-get? user-profiles tx-sender))
    )
    (if (is-none existing-profile)
        (begin
            (map-insert user-profiles tx-sender {
                reputation: u10,
                total-opinions: u0,
                consensus-contributions: u0,
                accuracy-score: u50,
                registration-block: u0
            })
            (var-set total-users (+ (var-get total-users) u1))
            (ok "User registered successfully")
        )
        (ok "User already registered")
    )
    )
)

(define-public (create-topic (title (string-ascii 200)) (description (string-ascii 500)))
    (let (
        (new-topic-id (+ (var-get topic-counter) u1))
    )
    (asserts! (> (len title) u0) ERR_INVALID_TOPIC)
    (asserts! (> (len description) u0) ERR_INVALID_TOPIC)
    
    (map-insert topics new-topic-id {
        title: title,
        description: description,
        creator: tx-sender,
        created-at: u0,
        is-active: true,
        total-opinions: u0,
        consensus-score: u0
    })
    
    (var-set topic-counter new-topic-id)
    (ok new-topic-id)
    )
)

(define-public (submit-opinion (topic-id uint) (content (string-ascii 500)) (confidence-level uint))
    (let (
        (new-opinion-id (+ (var-get opinion-counter) u1))
        (topic-info (unwrap! (map-get? topics topic-id) ERR_INVALID_TOPIC))
        (participation-key { topic-id: topic-id, user: tx-sender })
        (existing-participation (map-get? topic-participants participation-key))
        (opinion-weight (calculate-opinion-weight tx-sender confidence-level))
    )
    
    (asserts! (get is-active topic-info) ERR_INVALID_TOPIC)
    (asserts! (> (len content) u0) ERR_INVALID_OPINION)
    (asserts! (<= (len content) MAX_OPINION_LENGTH) ERR_INVALID_OPINION)
    (asserts! (and (>= confidence-level u1) (<= confidence-level u10)) ERR_INVALID_OPINION)
    (asserts! (is-none existing-participation) ERR_ALREADY_VOTED)
    
    ;; Register user if not already registered
    (unwrap-panic (register-user))
    
    ;; Create the opinion
    (map-insert opinions new-opinion-id {
        topic-id: topic-id,
        author: tx-sender,
        content: content,
        weight: opinion-weight,
        created-at: u0,
        upvotes: u0,
        downvotes: u0,
        confidence-level: confidence-level
    })
    
    ;; Record participation
    (map-insert topic-participants participation-key {
        has-submitted: true,
        opinion-id: new-opinion-id,
        participation-weight: opinion-weight
    })
    
    ;; Update topic statistics
    (map-set topics topic-id 
        (merge topic-info { total-opinions: (+ (get total-opinions topic-info) u1) })
    )
    
    ;; Update user profile
    (let (
        (current-profile (unwrap-panic (map-get? user-profiles tx-sender)))
    )
        (map-set user-profiles tx-sender
            (merge current-profile { 
                total-opinions: (+ (get total-opinions current-profile) u1)
            })
        )
    )
    
    ;; Update counters
    (var-set opinion-counter new-opinion-id)
    
    ;; Generate belief recommendation
    (generate-belief-recommendation tx-sender topic-id)
    
    (ok new-opinion-id)
    )
)

(define-public (vote-on-opinion (opinion-id uint) (vote-type (string-ascii 10)))
    (let (
        (opinion-info (unwrap! (map-get? opinions opinion-id) ERR_OPINION_NOT_FOUND))
        (vote-key { user: tx-sender, opinion-id: opinion-id })
        (existing-vote (map-get? user-votes vote-key))
        (voter-profile (unwrap! (map-get? user-profiles tx-sender) ERR_UNAUTHORIZED))
        (vote-weight (get reputation voter-profile))
    )
    
    (asserts! (is-none existing-vote) ERR_ALREADY_VOTED)
    (asserts! (or (is-eq vote-type "upvote") (is-eq vote-type "downvote")) ERR_INVALID_OPINION)
    
    ;; Record the vote
    (map-insert user-votes vote-key {
        vote-type: vote-type,
        weight: vote-weight
    })
    
    ;; Update opinion vote counts
    (if (is-eq vote-type "upvote")
        (map-set opinions opinion-id
            (merge opinion-info { 
                upvotes: (+ (get upvotes opinion-info) vote-weight)
            })
        )
        (map-set opinions opinion-id
            (merge opinion-info { 
                downvotes: (+ (get downvotes opinion-info) vote-weight)
            })
        )
    )
    
    ;; Update opinion author's reputation
    (if (is-eq vote-type "upvote")
        (update-user-reputation (get author opinion-info) 1)
        (update-user-reputation (get author opinion-info) -1)
    )
    
    (ok true)
    )
)

(define-public (get-personal-belief-suggestion (topic-id uint))
    (let (
        (topic-info (unwrap! (map-get? topics topic-id) ERR_INVALID_TOPIC))
        (user-suggestion (map-get? belief-suggestions tx-sender))
        (consensus-score (get consensus-score topic-info))
    )
    
    (if (>= consensus-score CONSENSUS_THRESHOLD)
        (ok {
            topic-id: topic-id,
            suggested-belief: "Follow the crowd consensus",
            confidence: consensus-score,
            reasoning: "Based on collective intelligence and democratic input"
        })
        (ok {
            topic-id: topic-id,
            suggested-belief: "Form your own opinion",
            confidence: u25,
            reasoning: "Insufficient consensus data available"
        })
    )
    )
)

;; Read-only functions
(define-read-only (get-topic (topic-id uint))
    (map-get? topics topic-id)
)

(define-read-only (get-opinion (opinion-id uint))
    (map-get? opinions opinion-id)
)

(define-read-only (get-user-profile (user principal))
    (map-get? user-profiles user)
)

(define-read-only (get-topic-consensus (topic-id uint))
    (let (
        (topic-info (map-get? topics topic-id))
    )
    (match topic-info
        topic (get consensus-score topic)
        u0
    )
    )
)

(define-read-only (get-contract-stats)
    {
        total-topics: (var-get topic-counter),
        total-opinions: (var-get opinion-counter),
        total-users: (var-get total-users)
    }
)

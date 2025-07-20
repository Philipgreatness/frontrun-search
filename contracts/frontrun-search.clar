;; frontrun-search
;; A decentralized marketplace for detecting and preventing blockchain transaction frontrunning

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-SEARCH-NOT-FOUND (err u101))
(define-constant ERR-INVALID-PARAMETERS (err u102))
(define-constant ERR-ALREADY-REGISTERED (err u103))
(define-constant ERR-INSUFFICIENT-STAKE (err u104))
(define-constant ERR-LIMIT-EXCEEDED (err u105))

;; Constants
(define-constant SEARCH-STATUS-ACTIVE u1)
(define-constant SEARCH-STATUS-COMPLETED u2)
(define-constant SEARCH-STATUS-CANCELLED u3)

(define-constant MIN-STAKE-AMOUNT u1000) ;; Minimum stake for registering a search
(define-constant MAX-ACTIVE-SEARCHES u10) ;; Maximum concurrent active searches per user

;; Data Maps
(define-map frontrun-searches
  { search-id: uint }
  {
    creator: principal,
    target-address: (string-ascii 100),
    target-contract: (string-ascii 100),
    description: (string-utf8 500),
    reward-amount: uint,
    status: uint,
    stake-amount: uint,
    created-at: uint
  }
)

(define-map user-search-counts
  { user: principal }
  { active-searches: uint }
)

;; Data Variables
(define-data-var search-id-counter uint u1)
(define-data-var contract-owner principal tx-sender)

;; Private Functions
(define-private (generate-search-id)
  (let ((current-id (var-get search-id-counter)))
    (var-set search-id-counter (+ current-id u1))
    current-id
  )
)

(define-private (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner))
)

(define-private (increment-user-search-count (user principal))
  (let ((current-count (default-to { active-searches: u0 } (map-get? user-search-counts { user: user }))))
    (map-set user-search-counts
      { user: user }
      { active-searches: (+ (get active-searches current-count) u1) }
    )
  )
)

(define-private (decrement-user-search-count (user principal))
  (let ((current-count (default-to { active-searches: u0 } (map-get? user-search-counts { user: user }))))
    (map-set user-search-counts
      { user: user }
      { active-searches: (- (get active-searches current-count) u1) }
    )
  )
)

;; Read-only Functions
(define-read-only (get-search (search-id uint))
  (map-get? frontrun-searches { search-id: search-id })
)

(define-read-only (get-user-active-search-count (user principal))
  (default-to u0 (get active-searches (map-get? user-search-counts { user: user })))
)

;; Public Functions
(define-public (create-frontrun-search
  (target-address (string-ascii 100))
  (target-contract (string-ascii 100))
  (description (string-utf8 500))
  (reward-amount uint)
)
  (let (
    (new-search-id (generate-search-id))
    (active-search-count (get-user-active-search-count tx-sender))
  )
    ;; Validate inputs
    (asserts! (> reward-amount u0) ERR-INVALID-PARAMETERS)
    (asserts! (< active-search-count MAX-ACTIVE-SEARCHES) ERR-LIMIT-EXCEEDED)
    
    ;; Transfer reward stake
    (unwrap! (stx-transfer? reward-amount tx-sender (as-contract tx-sender)) ERR-INSUFFICIENT-STAKE)
    
    ;; Create search entry
    (map-set frontrun-searches
      { search-id: new-search-id }
      {
        creator: tx-sender,
        target-address: target-address,
        target-contract: target-contract,
        description: description,
        reward-amount: reward-amount,
        status: SEARCH-STATUS-ACTIVE,
        stake-amount: reward-amount,
        created-at: block-height
      }
    )
    
    ;; Update user's active search count
    (increment-user-search-count tx-sender)
    
    (ok new-search-id)
  )
)

(define-public (cancel-frontrun-search (search-id uint))
  (let (
    (search (unwrap! (map-get? frontrun-searches { search-id: search-id }) ERR-SEARCH-NOT-FOUND))
  )
    ;; Ensure only creator can cancel
    (asserts! (is-eq tx-sender (get creator search)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status search) SEARCH-STATUS-ACTIVE) ERR-INVALID-PARAMETERS)
    
    ;; Return stake to creator
    (as-contract
      (unwrap! (stx-transfer? (get stake-amount search) tx-sender (get creator search)) ERR-INSUFFICIENT-STAKE)
    )
    
    ;; Update search status
    (map-set frontrun-searches
      { search-id: search-id }
      (merge search { status: SEARCH-STATUS-CANCELLED })
    )
    
    ;; Decrement user's active search count
    (decrement-user-search-count tx-sender)
    
    (ok true)
  )
)

(define-public (report-frontrun-search 
  (search-id uint)
  (evidence (string-utf8 500))
)
  (let (
    (search (unwrap! (map-get? frontrun-searches { search-id: search-id }) ERR-SEARCH-NOT-FOUND))
  )
    ;; Validate search is active
    (asserts! (is-eq (get status search) SEARCH-STATUS-ACTIVE) ERR-INVALID-PARAMETERS)
    
    ;; Transfer reward to reporter if evidence is strong
    (as-contract
      (unwrap! (stx-transfer? (get stake-amount search) tx-sender (get creator search)) ERR-INSUFFICIENT-STAKE)
    )
    
    ;; Update search status
    (map-set frontrun-searches
      { search-id: search-id }
      (merge search { status: SEARCH-STATUS-COMPLETED })
    )
    
    ;; Decrement creator's active search count
    (decrement-user-search-count (get creator search))
    
    (ok true)
  )
)

;; Administrative Functions
(define-public (update-contract-owner (new-owner principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)
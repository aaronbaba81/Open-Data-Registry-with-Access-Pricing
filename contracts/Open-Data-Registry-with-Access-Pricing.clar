(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-dataset-not-found (err u101))
(define-constant err-insufficient-payment (err u102))
(define-constant err-unauthorized (err u103))
(define-constant err-dataset-exists (err u104))
(define-constant err-invalid-price (err u105))

(define-constant err-already-rated (err u106))
(define-constant err-invalid-rating (err u107))
(define-constant err-no-access-history (err u108))

(define-data-var next-dataset-id uint u1)
(define-data-var platform-fee uint u50)

(define-map datasets
  uint
  {
    owner: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    data-hash: (string-ascii 64),
    base-price: uint,
    access-count: uint,
    created-at: uint,
    license-type: (string-ascii 50),
    is-active: bool
  }
)

(define-map dataset-access
  { dataset-id: uint, user: principal }
  {
    purchased-at: uint,
    expires-at: uint,
    access-level: (string-ascii 20)
  }
)

(define-map user-balances
  principal
  uint
)

(define-map pricing-multipliers
  uint
  uint
)

(define-read-only (get-dataset (dataset-id uint))
  (map-get? datasets dataset-id)
)

(define-read-only (get-user-access (dataset-id uint) (user principal))
  (map-get? dataset-access { dataset-id: dataset-id, user: user })
)

(define-read-only (get-user-balance (user principal))
  (default-to u0 (map-get? user-balances user))
)

(define-read-only (get-current-price (dataset-id uint))
  (match (map-get? datasets dataset-id)
    dataset-info
    (let (
      (base-price (get base-price dataset-info))
      (access-count (get access-count dataset-info))
      (multiplier (default-to u100 (map-get? pricing-multipliers dataset-id)))
    )
    (/ (* base-price multiplier) u100)
    )
    u0
  )
)

(define-read-only (get-platform-fee)
  (var-get platform-fee)
)

(define-read-only (has-valid-access (dataset-id uint) (user principal))
  (match (map-get? dataset-access { dataset-id: dataset-id, user: user })
    access-info
    (> (get expires-at access-info) stacks-block-height)
    false
  )
)

(define-public (register-dataset (title (string-ascii 100)) (description (string-ascii 500)) (data-hash (string-ascii 64)) (base-price uint) (license-type (string-ascii 50)))
  (let (
    (dataset-id (var-get next-dataset-id))
  )
  (asserts! (> base-price u0) err-invalid-price)
  (asserts! (is-none (map-get? datasets dataset-id)) err-dataset-exists)
  (map-set datasets dataset-id {
    owner: tx-sender,
    title: title,
    description: description,
    data-hash: data-hash,
    base-price: base-price,
    access-count: u0,
    created-at: stacks-block-height,
    license-type: license-type,
    is-active: true
  })
  (var-set next-dataset-id (+ dataset-id u1))
  (map-set pricing-multipliers dataset-id u100)
  (ok dataset-id)
  )
)

(define-public (purchase-access (dataset-id uint) (duration uint))
  (let (
    (dataset-info (unwrap! (map-get? datasets dataset-id) err-dataset-not-found))
    (current-price (get-current-price dataset-id))
    (total-cost current-price)
    (user-balance (get-user-balance tx-sender))
    (platform-fee-amount (/ (* total-cost (var-get platform-fee)) u1000))
    (owner-payment (- total-cost platform-fee-amount))
  )
  (asserts! (get is-active dataset-info) err-dataset-not-found)
  (asserts! (>= user-balance total-cost) err-insufficient-payment)
  (map-set user-balances tx-sender (- user-balance total-cost))
  (map-set user-balances (get owner dataset-info) 
    (+ (get-user-balance (get owner dataset-info)) owner-payment))
  (map-set user-balances contract-owner 
    (+ (get-user-balance contract-owner) platform-fee-amount))
  (map-set dataset-access { dataset-id: dataset-id, user: tx-sender } {
    purchased-at: stacks-block-height,
    expires-at: (+ stacks-block-height duration),
    access-level: "full"
  })
  (map-set datasets dataset-id 
    (merge dataset-info { access-count: (+ (get access-count dataset-info) u1) }))
  (try! (update-pricing-multiplier dataset-id))
  (ok true)
  )
)

(define-public (deposit-funds (amount uint))
  (begin
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (map-set user-balances tx-sender (+ (get-user-balance tx-sender) amount))
    (ok true)
  )
)

(define-public (withdraw-funds (amount uint))
  (let (
    (user-balance (get-user-balance tx-sender))
  )
  (asserts! (>= user-balance amount) err-insufficient-payment)
  (map-set user-balances tx-sender (- user-balance amount))
  (as-contract (stx-transfer? amount tx-sender tx-sender))
  )
)

(define-public (update-dataset-status (dataset-id uint) (is-active bool))
  (let (
    (dataset-info (unwrap! (map-get? datasets dataset-id) err-dataset-not-found))
  )
  (asserts! (is-eq tx-sender (get owner dataset-info)) err-unauthorized)
  (map-set datasets dataset-id (merge dataset-info { is-active: is-active }))
  (ok true)
  )
)

(define-public (update-base-price (dataset-id uint) (new-price uint))
  (let (
    (dataset-info (unwrap! (map-get? datasets dataset-id) err-dataset-not-found))
  )
  (asserts! (is-eq tx-sender (get owner dataset-info)) err-unauthorized)
  (asserts! (> new-price u0) err-invalid-price)
  (map-set datasets dataset-id (merge dataset-info { base-price: new-price }))
  (ok true)
  )
)

(define-public (set-platform-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-fee u100) err-invalid-price)
    (var-set platform-fee new-fee)
    (ok true)
  )
)

(define-private (update-pricing-multiplier (dataset-id uint))
  (let (
    (dataset-info (unwrap! (map-get? datasets dataset-id) err-dataset-not-found))
    (access-count (get access-count dataset-info))
    (new-multiplier (if (> access-count u10) 
      (+ u100 (* access-count u5)) 
      u100))
  )
  (map-set pricing-multipliers dataset-id new-multiplier)
  (ok true)
  ) 
)


(define-map dataset-ratings
  { dataset-id: uint, user: principal }
  {
    rating: uint,
    review: (string-ascii 200),
    submitted-at: uint
  }
)

(define-map dataset-rating-stats
  uint
  {
    total-ratings: uint,
    sum-ratings: uint,
    average-rating: uint
  }
)

(define-read-only (get-dataset-rating (dataset-id uint))
  (default-to 
    { total-ratings: u0, sum-ratings: u0, average-rating: u0 }
    (map-get? dataset-rating-stats dataset-id)
  )
)

(define-read-only (get-user-rating (dataset-id uint) (user principal))
  (map-get? dataset-ratings { dataset-id: dataset-id, user: user })
)

(define-public (rate-dataset (dataset-id uint) (rating uint) (review (string-ascii 200)))
  (let (
    (dataset-info (unwrap! (map-get? datasets dataset-id) err-dataset-not-found))
    (user-access (unwrap! (map-get? dataset-access { dataset-id: dataset-id, user: tx-sender }) err-no-access-history))
    (existing-rating (map-get? dataset-ratings { dataset-id: dataset-id, user: tx-sender }))
    (current-stats (get-dataset-rating dataset-id))
  )
  (asserts! (is-none existing-rating) err-already-rated)
  (asserts! (and (>= rating u1) (<= rating u5)) err-invalid-rating)
  (map-set dataset-ratings { dataset-id: dataset-id, user: tx-sender } {
    rating: rating,
    review: review,
    submitted-at: stacks-block-height
  })
  (let (
    (new-total (+ (get total-ratings current-stats) u1))
    (new-sum (+ (get sum-ratings current-stats) rating))
    (new-average (/ (* new-sum u100) new-total))
  )
  (map-set dataset-rating-stats dataset-id {
    total-ratings: new-total,
    sum-ratings: new-sum,
    average-rating: new-average
  })
  )
  (ok true)
  )
)
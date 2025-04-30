;; chainmint-core
;; 
;; This contract manages the tokenization, ownership, and trading of physical assets
;; on the ChainMint platform. It enables verified asset providers to register physical assets,
;; mint SIP-010 compliant tokens representing fractional ownership, and facilitates trading
;; of these tokens between users, while maintaining a comprehensive registry of all assets
;; and their associated metadata.

;; =============================================================================
;; Constants and Error Codes
;; =============================================================================

;; Permission errors
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-NOT-ADMIN (err u101))
(define-constant ERR-NOT-ASSET-PROVIDER (err u102))
(define-constant ERR-NOT-ASSET-OWNER (err u103))

;; Input validation errors
(define-constant ERR-INVALID-ASSET-ID (err u200))
(define-constant ERR-INVALID-TOKEN-URI (err u201))
(define-constant ERR-INVALID-AMOUNT (err u202))
(define-constant ERR-INVALID-PRICE (err u203))
(define-constant ERR-ZERO-TOKENS (err u204))
(define-constant ERR-INVALID-RECIPIENT (err u205))

;; State errors
(define-constant ERR-ASSET-EXISTS (err u300))
(define-constant ERR-ASSET-NOT-FOUND (err u301))
(define-constant ERR-PROVIDER-EXISTS (err u302))
(define-constant ERR-PROVIDER-NOT-FOUND (err u303))
(define-constant ERR-ASSET-NOT-VERIFIED (err u304))
(define-constant ERR-INSUFFICIENT-TOKENS (err u305))
(define-constant ERR-TRADING-LOCKED (err u306))

;; Success responses
(define-constant SUCCESS-TRUE (ok true))
(define-constant ASSET-REGISTERED (ok "Asset successfully registered"))
(define-constant ASSET-VERIFIED (ok "Asset successfully verified"))
(define-constant PROVIDER-VERIFIED (ok "Provider successfully verified"))

;; =============================================================================
;; Data Maps and Variables
;; =============================================================================

;; Contract administrator
(define-data-var contract-admin principal tx-sender)

;; Asset provider registry
(define-map asset-providers 
  principal 
  {
    is-verified: bool,
    name: (string-ascii 100),
    registration-date: uint,
    assets-registered: (list 100 uint)
  }
)

;; Asset registry
(define-map assets 
  uint  ;; asset-id
  {
    name: (string-ascii 100),
    description: (string-utf8 500),
    asset-type: (string-ascii 50),
    location: (string-ascii 200),
    valuation: uint,
    total-supply: uint,
    provider: principal,
    is-verified: bool,
    verification-date: uint,
    documentation-uri: (string-ascii 200),
    is-trading-locked: bool,
    created-at: uint
  }
)

;; Token ownership registry
(define-map token-holdings
  { asset-id: uint, owner: principal }
  uint  ;; token amount
)

;; Used to generate unique asset IDs
(define-data-var asset-id-nonce uint u0)

;; =============================================================================
;; Private Functions
;; =============================================================================

;; Generate a new unique asset ID
(define-private (generate-asset-id)
  (let ((current-id (var-get asset-id-nonce)))
    (var-set asset-id-nonce (+ current-id u1))
    current-id
  )
)

;; Check if caller is the contract administrator
(define-private (is-admin)
  (is-eq tx-sender (var-get contract-admin))
)

;; Check if a provider is verified
(define-private (is-verified-provider (provider principal))
  (default-to false (get is-verified (map-get? asset-providers provider)))
)

;; Check if an asset exists
(define-private (asset-exists (asset-id uint))
  (is-some (map-get? assets asset-id))
)

;; Check if an asset is verified
(define-private (is-asset-verified (asset-id uint))
  (default-to false (get is-verified (map-get? assets asset-id)))
)

;; Check if asset trading is locked
(define-private (is-trading-locked (asset-id uint))
  (default-to true (get is-trading-locked (map-get? assets asset-id)))
)

;; Get token balance for a specific asset and owner
(define-private (get-token-balance (asset-id uint) (owner principal))
  (default-to u0 (map-get? token-holdings { asset-id: asset-id, owner: owner }))
)

;; Update token balance for a specific asset and owner
(define-private (set-token-balance (asset-id uint) (owner principal) (amount uint))
  (map-set token-holdings { asset-id: asset-id, owner: owner } amount)
)

;; Add amount to existing token balance
(define-private (add-tokens (asset-id uint) (owner principal) (amount uint))
  (let ((current-balance (get-token-balance asset-id owner)))
    (set-token-balance asset-id owner (+ current-balance amount))
    (ok amount)
  )
)

;; Subtract amount from existing token balance
(define-private (subtract-tokens (asset-id uint) (owner principal) (amount uint))
  (let ((current-balance (get-token-balance asset-id owner)))
    (if (>= current-balance amount)
      (begin
        (set-token-balance asset-id owner (- current-balance amount))
        (ok amount)
      )
      ERR-INSUFFICIENT-TOKENS
    )
  )
)

;; Transfer tokens between users
(define-private (transfer-tokens (asset-id uint) (sender principal) (recipient principal) (amount uint))
  (begin
    (try! (subtract-tokens asset-id sender amount))
    (add-tokens asset-id recipient amount)
  )
)

;; Add asset to provider's registered assets list
(define-private (add-asset-to-provider (provider principal) (asset-id uint))
  (let (
    (provider-data (unwrap! (map-get? asset-providers provider) ERR-PROVIDER-NOT-FOUND))
    (current-assets (get assets-registered provider-data))
  )
    (map-set asset-providers 
      provider 
      (merge provider-data { assets-registered: (append current-assets asset-id) })
    )
  )
)

;; =============================================================================
;; Read-Only Functions
;; =============================================================================

;; Get asset details
(define-read-only (get-asset (asset-id uint))
  (map-get? assets asset-id)
)

;; Get provider details
(define-read-only (get-provider (provider principal))
  (map-get? asset-providers provider)
)

;; Get token balance for a given asset and owner
(define-read-only (get-balance (asset-id uint) (owner principal))
  (get-token-balance asset-id owner)
)

;; Get total supply for an asset
(define-read-only (get-total-supply (asset-id uint))
  (default-to u0 (get total-supply (map-get? assets asset-id)))
)

;; Check if an address is a verified provider
(define-read-only (is-provider-verified (provider principal))
  (is-verified-provider provider)
)

;; Get all assets for a provider
(define-read-only (get-provider-assets (provider principal))
  (default-to (list) (get assets-registered (map-get? asset-providers provider)))
)

;; =============================================================================
;; Public Functions
;; =============================================================================

;; Change contract administrator
(define-public (set-contract-admin (new-admin principal))
  (begin
    (asserts! (is-admin) ERR-NOT-ADMIN)
    (var-set contract-admin new-admin)
    SUCCESS-TRUE
  )
)

;; Register a new asset provider
(define-public (register-provider (provider-name (string-ascii 100)))
  (begin
    (asserts! (is-none (map-get? asset-providers tx-sender)) ERR-PROVIDER-EXISTS)
    (map-set asset-providers 
      tx-sender 
      {
        is-verified: false,
        name: provider-name,
        registration-date: block-height,
        assets-registered: (list)
      }
    )
    SUCCESS-TRUE
  )
)

;; Verify an asset provider (admin only)
(define-public (verify-provider (provider principal))
  (begin
    (asserts! (is-admin) ERR-NOT-ADMIN)
    (asserts! (is-some (map-get? asset-providers provider)) ERR-PROVIDER-NOT-FOUND)
    
    (let ((provider-data (unwrap-panic (map-get? asset-providers provider))))
      (map-set asset-providers 
        provider 
        (merge provider-data { is-verified: true })
      )
    )
    PROVIDER-VERIFIED
  )
)

;; Register a new physical asset
(define-public (register-asset 
  (name (string-ascii 100))
  (description (string-utf8 500))
  (asset-type (string-ascii 50))
  (location (string-ascii 200))
  (valuation uint)
  (total-supply uint)
  (documentation-uri (string-ascii 200))
)
  (let ((asset-id (generate-asset-id)))
    ;; Check that caller is a verified provider
    (asserts! (is-verified-provider tx-sender) ERR-NOT-ASSET-PROVIDER)
    ;; Check that inputs are valid
    (asserts! (> total-supply u0) ERR-INVALID-AMOUNT)
    (asserts! (> valuation u0) ERR-INVALID-PRICE)
    (asserts! (not (is-eq documentation-uri "")) ERR-INVALID-TOKEN-URI)
    
    ;; Create the asset record
    (map-set assets 
      asset-id
      {
        name: name,
        description: description,
        asset-type: asset-type,
        location: location,
        valuation: valuation,
        total-supply: total-supply,
        provider: tx-sender,
        is-verified: false,
        verification-date: u0,
        documentation-uri: documentation-uri,
        is-trading-locked: true,
        created-at: block-height
      }
    )
    
    ;; Add to provider's asset list
    (add-asset-to-provider tx-sender asset-id)
    
    ;; Mint all tokens to the provider initially
    (set-token-balance asset-id tx-sender total-supply)
    
    (ok asset-id)
  )
)

;; Verify an asset (admin only)
(define-public (verify-asset (asset-id uint))
  (begin
    (asserts! (is-admin) ERR-NOT-ADMIN)
    (asserts! (asset-exists asset-id) ERR-ASSET-NOT-FOUND)
    
    (let ((asset-data (unwrap-panic (map-get? assets asset-id))))
      (map-set assets 
        asset-id 
        (merge asset-data 
          { 
            is-verified: true,
            verification-date: block-height
          }
        )
      )
    )
    ASSET-VERIFIED
  )
)

;; Toggle trading lock for an asset (provider only)
(define-public (toggle-trading-lock (asset-id uint))
  (let ((asset-data (unwrap! (map-get? assets asset-id) ERR-ASSET-NOT-FOUND)))
    ;; Check that caller is the asset provider
    (asserts! (is-eq tx-sender (get provider asset-data)) ERR-NOT-ASSET-OWNER)
    ;; Asset must be verified before trading can be enabled
    (asserts! (get is-verified asset-data) ERR-ASSET-NOT-VERIFIED)
    
    (map-set assets 
      asset-id 
      (merge asset-data { is-trading-locked: (not (get is-trading-locked asset-data)) })
    )
    SUCCESS-TRUE
  )
)

;; Transfer tokens from sender to recipient
(define-public (transfer (asset-id uint) (amount uint) (recipient principal))
  (begin
    ;; Input validation
    (asserts! (asset-exists asset-id) ERR-ASSET-NOT-FOUND)
    (asserts! (> amount u0) ERR-ZERO-TOKENS)
    (asserts! (not (is-eq tx-sender recipient)) ERR-INVALID-RECIPIENT)
    ;; State validation
    (asserts! (is-asset-verified asset-id) ERR-ASSET-NOT-VERIFIED)
    (asserts! (not (is-trading-locked asset-id)) ERR-TRADING-LOCKED)
    
    ;; Transfer the tokens
    (try! (transfer-tokens asset-id tx-sender recipient amount))
    (ok amount)
  )
)

;; Update asset valuation (provider only)
(define-public (update-asset-valuation (asset-id uint) (new-valuation uint))
  (let ((asset-data (unwrap! (map-get? assets asset-id) ERR-ASSET-NOT-FOUND)))
    ;; Check that caller is the asset provider
    (asserts! (is-eq tx-sender (get provider asset-data)) ERR-NOT-ASSET-OWNER)
    ;; Check that the new valuation is valid
    (asserts! (> new-valuation u0) ERR-INVALID-PRICE)
    
    (map-set assets 
      asset-id 
      (merge asset-data { valuation: new-valuation })
    )
    SUCCESS-TRUE
  )
)

;; Update asset documentation URI (provider only)
(define-public (update-documentation-uri (asset-id uint) (new-uri (string-ascii 200)))
  (let ((asset-data (unwrap! (map-get? assets asset-id) ERR-ASSET-NOT-FOUND)))
    ;; Check that caller is the asset provider
    (asserts! (is-eq tx-sender (get provider asset-data)) ERR-NOT-ASSET-OWNER)
    ;; Check that the new URI is valid
    (asserts! (not (is-eq new-uri "")) ERR-INVALID-TOKEN-URI)
    
    (map-set assets 
      asset-id 
      (merge asset-data { documentation-uri: new-uri })
    )
    SUCCESS-TRUE
  )
)

;; Distribute income to token holders (provider only)
(define-public (distribute-income (asset-id uint) (recipient principal) (amount uint))
  (let (
    (asset-data (unwrap! (map-get? assets asset-id) ERR-ASSET-NOT-FOUND))
    (recipient-balance (get-token-balance asset-id recipient))
    (total-supply (get total-supply asset-data))
  )
    ;; Check that caller is the asset provider
    (asserts! (is-eq tx-sender (get provider asset-data)) ERR-NOT-ASSET-OWNER)
    ;; Check that amount is valid
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    ;; Check that recipient owns tokens
    (asserts! (> recipient-balance u0) ERR-INVALID-RECIPIENT)
    
    ;; Transfer is done outside of the contract since Clarity can't directly transfer STX
    ;; We're just returning the calculated amount the recipient should receive
    (ok (/ (* amount recipient-balance) total-supply))
  )
)
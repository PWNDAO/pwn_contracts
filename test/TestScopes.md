PWN contract
Deployment
✓ Should deploy PWN with links to Deed & Vault
✓ Should deploy Vault with a link to PWN
✓ Should deploy Deed with a link to PWN
✓ Should set initial balances

Workflow - New deeds with arbitrary collateral
✓ Should be possible to create an ERC20 deed (79ms)
✓ Should be possible to create an ERC721 deed (75ms)
✓ Should be possible to create an ERC1155 deed (68ms)

Workflow - New deeds with arbitrary collateral
✓ Should be possible to revoke an ERC20 deed (110ms)
✓ Should be possible to revoke an ERC721 deed (104ms)
✓ Should be possible to revoke an ERC1155 deed (102ms)

Workflow - Offers handling
✓ Should be possible make an offer (112ms)
✓ Should be possible to revoke an offer (135ms)
✓ Should be possible to accept an offer (201ms)

Workflow - Settlement
✓ Should be possible to pay back (272ms)
✓ Should be possible to claim after deed was paid (309ms)
✓ Should be possible to claim if deed wasn't paid (226ms)


Missing:

MultiToken
Transfer
- Should call transfer on ERC20 token
- Should fail when passing ERC20 category without ERC20 token address
- Should call transfer from current address on ERC721
- Should fail when passing ERC721 category without ERC721 address
- Should call safe transfer from current address on ERC1155 token
- SHould update amount on ERC1155 token transfer
- Should fail when passing ERC1155 category without ERC1155 token address
- Should fail when passing unsupported category

TransferFrom
- Should call transfer from on ERC20 token
- Should fail when passing ERC20 category without ERC20 token address
- Should call transfer from on ERC721
- Should fail when passing ERC721 category without ERC721 address
- Should call safe transfer from on ERC1155 token
- SHould update amount on ERC1155 token transfer
- Should fail when passing ERC1155 category without ERC1155 token address
- Should fail when passing unsupported category

BalanceOf
- Should return balance of ERC20 token
- Should fail when passing ERC20 category without ERC20 token address
- Should return ownership of ERC721
- Should fail when passing ERC721 category without ERC721 address
- Should return balance ERC1155 token
- Should fail when passing ERC1155 category without ERC1155 token address
- Should fail when passing unsupported category

ApproveAsset
- Should call approve on ERC20 token
- Should fail when passing ERC20 category without ERC20 token address
- Should call approve on ERC721
- Should fail when passing ERC721 category without ERC721 address
- Should call set approval for all on ERC1155 token
- Should fail when passing ERC1155 category without ERC1155 token address
- Should fail when passing unsupported category


PWN contract
New deed
- Should be able to create ERC20 deed
- Should be able to create ERC721 deed
- Should be able to crate ERC1155 deed
- Should fail for unknown asset category
- Should fail for expiration duration smaller than min duration
- Should emit NewDeed event
- Should return newly created deed ID
- Should send borrower collateral to vault
- Should mint new deed in correct state

Revoke deed
- Should fail when sender is not borrower
- Should fail when deed is not in new/open state
- Should send deed collateral to borrower from vault
- Should burn deed token
- Should emit DeedRevoked event

Make offer
- Should be able to make ERC20 offer
- Should be able to make ERC721 offer
- Should be able to make ERC1155 offer
- Should fail for unknown asset category
- Should fail when deed is not in new/open state
- Should set new offer to the deed
- Should emit NewOffer event
- Should return new offer hash as bytes

Revoke offer
- Should fail when sender is not the offer maker
- Should fail when deed of the offer is not in new/open state
- Should remove offer from deed
- Should emit OfferRevoked event

Accept offer
- Should fail when sender is not the borrower
- Should fail when deed is not in new/open state
- Should set offer as accepted in deed
- Should update deed to running state
- Should send lender asset to borrower
- Should send deed token to lender
- Should emit OfferAccepted event
- Should return true if successful

Pay back
- Should fail when sender is not the borrower
- Should fail when deed is not in running state
- Should update deed to paid back state
- Should send pay back amount to vault
- Should send deed collateral to borrower from vault
- Should emit PaidBack event
- Should return true if successful

Claim deed
- Should fail when sender is not deed owner
- Should fail when deed is not in paid back nor expired state
- Should send collateral from vault to lender when deed is expired
- Should send paid back amount from vault to lender when deed is paid back
- Should emit DeedClaimed event
- Should burn deed token
- Should return true if successful

Change min duration
- Should fail when sender is not owner
- Should set new min duration
- Shoudl emit MinDurationChange event


PWNDeed contract
Constructor
- Should set correct owner
- Should set correct uri

Mint
- Should fail when sender is not PWN contract
- Should mint deed ERC1155 token
- Should save deed data
- Should return minted deed ID

Burn
- Should fail when sender is not PWN contract
- Should burn deed ERC1155 token
- Should delete deed data

Set offer
- Should fail when sender is not PWN contract
- Should save offer data
- Should set offer to deed
- Should return offer hash as bytes

Delete offer
- Should fail when sender is not PWN contract
- Should delete offer

Set credit
- Should fail when sender is not PWN contract
- Should set offer as accepted in deed
- Should delete deed pending offers

Change status
- Should fail when sender is not PWN contract
- Should set deed state

beforeTokenTransfer??

Get deed status
- Should return none/dead state
- Should return new/open state
- Should return running state
- Should return paid back state
- Should return expired state

Get expiration
- Should return deed expiration

Get borrower
- Should return borrower address

Get deed asset
- Should return deed asset

Get offers
- Should return deed pending offers byte array

Get accepted offer
- Should return deed accepted offer

Get deed ID
- Should return deed ID

Get offer asset
- Should return offer asset

To be paid
- Should return offer to be paid value

Get lender
- Should return lender address

Set PWN
- Should fail when sender is not owner
- Should set PWN address


PWNVault
Constructor
- Should set correct owner

Push
- Should fail when sender is not PWN contract
- Should send asset from address to vault
- Should emit VaultPush event
- Should return true if successful

Pull
- Should fail when sender is not PWN contract
- Should send asset from vault to address
- Should emit VaultPull event
- Should return true if successful

PullProxy
- Should fail when sender is not PWN contract
- Should send asset from address to address
- Should emit VaultProxy event
- Should return true if successful

On ERC1155 received
- Should return correct bytes

On ERC1155 batch received
- Should return correct bytes

Set PWN
- Should fail when sender is not owner
- Should set PWN address

Supports interface
- Should return true for supported interfaces

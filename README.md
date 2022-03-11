# PWN Finance
Smart contracts enabling p2p loans using arbitrary collateral (supporting ERC20, ERC721, ERC1155 standards).

## Architecture
### PWN (logic)
PWN is the core interface users are expected to use (also the only interactive contract allowing for permissionless external calls).
The contract defines the workflow functionality and handles the market making. Allowing to:
- Create Deeds with off-chain signed offer
- Pay back loans
- Claim collateral or credit

### PWN Deed 
PWN Deed is an PWN contextual extension of a standard ERC1155 token. Each Deed is defined as an ERC1155 NFT. 
The PWN Deed contract allows for reading the contextual information of the Deeds (like status, expirations, etc.) 
but all of its contract features can only be called through the PWN (logic) contract. 

### PWN Vault
PWN Vault is the holder contract for the locked in collateral and paid back credit.
The contract can only be operated through the PWN (logic) contract. 
All approval of tokens utilized within the PWN context has to be done towards the PWN Vault address - 
as ultimately it's the contract accessing the tokens. 

### MultiToken library
https://github.com/PWNFinance/MultiToken
The library defines a token asset as a struct of token identifiers. 
It wraps transfer, allowance & balance check calls of the following token standards:
- ERC20
- ERC721 
- ERC1155

Unifying the function calls used within the PWN context (not having to worry about handling those individually).

### High level contract architecture
![PWN contracts interaction](.github/img/contracts_interaction.png "PWN contracts interaction")

## PWN Deed
PWN Deed token is a tokenized representation of a loan which can aquire different states:
- Dead/None - Deed is not created or have been claimed and can be burned.
- Running - Deed is created by passing offer data and offer siganture signed by a lender.
- Paid back - Deed had been fully paid back before expiration date. Deed owner is able to claim lended credit + interest.
- Expired - Deed had not been fully paid back before expiration date. Deed owner is able to claim collateral.

### State diagram
![Deed state diagram](.github/img/deed_state.png "Deed state diagram")

## User flow
Following diagram shows deed lifecycle with borrower, lender and pwn protocol interactions.

1. Borrower starts by signaling desire to take a loan with desired loan parameters (collateral asset, loan asset, amount, duration).
2. Lender makes an offer to arbitray asset and signs it off-chain. Lender can revoke singed offer anytime by making on-chain transaction.
3. Borrower can accept any offer which is made to collateral he/she owns.

    a) collateral is transferred to PWNVaul contract (should be approved for PWNVault)

    b) loan asset is transferred from lender to borrower (should be approved for PWNVault)

    c) deed token is minted to represent a loan and transferred to a lender

4. Borrower should repay a loan anytime before expiration.

    a) repay amount is transferred to PWNVault contract (should be approved for PWNVault)

    b) collateral is transferred back to borrower

5. Deed owner can claim repay amount.

    a) repay amount is transferred to a deed owner

    b) deed token is burned

6. In case borrower is not able to repay loan in time, lender can claim borrowers collateral and borrower keeps the loan asset.

![Basic user flow](.github/img/user_flow.png "Basic user flow")

## Offer types
Lender can choose between two types while making an offer. Basic and flexible.

### Basic
Basic offer is where lender is setting all loan parameters up-front and borrower has an option to accept of not. Nothing else.

### Flexible
With flexible offers, lender can give borrower additional flexibility by not providing concrete values but rather give borrower ranges for several parameters. When accepting an offer, borrower has to provide concrete values to proceed. This increases a lenders chance to have their offer accepted as it could be accepted by more borrowers.

Flexible parameters are: collateral id, loan amount, loan duration.

## Deployed addresses
### Mainnet
- PWN deployed at: _TBD_
- PWNDeed deployed at: _TBD_
- PWNVault deployed at: _TBD_

### Rinkeby testnet
- PWN deployed at: _TBD_
- PWNDeed deployed at: _TBD_
- PWNVault deployed at: _TBD_

### OpenSea shortcuts
- PWN Deeds Listings: https://opensea.io/collection/pwn-deed
- Collateral Collection: https://opensea.io/TBD

# PWN is hiring!
https://www.notion.so/PWN-is-hiring-f5a49899369045e39f41fc7e4c7b5633

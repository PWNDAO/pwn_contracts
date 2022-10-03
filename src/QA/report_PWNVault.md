## Sūrya's Description Report

### Files Description Table


|  File Name  |  SHA-1 Hash  |
|-------------|--------------|
| ../PWNVault.sol | c18f87f7469bc8799c277447b1ab10c74d326224 |


### Contracts Description Table


|  Contract  |         Type        |       Bases      |                  |                 |
|:----------:|:-------------------:|:----------------:|:----------------:|:---------------:|
|     └      |  **Function Name**  |  **Visibility**  |  **Mutability**  |  **Modifiers**  |
||||||
| **PWNVault** | Implementation | Ownable, IERC1155Receiver |||
| └ | <Constructor> | Public ❗️ | 🛑  | Ownable IERC1155Receiver |
| └ | push | External ❗️ | 🛑  | onlyPWN |
| └ | pull | External ❗️ | 🛑  | onlyPWN |
| └ | pullProxy | External ❗️ | 🛑  | onlyPWN |
| └ | onERC1155Received | External ❗️ |   |NO❗️ |
| └ | onERC1155BatchReceived | External ❗️ |   |NO❗️ |
| └ | setPWN | External ❗️ | 🛑  | onlyOwner |
| └ | supportsInterface | External ❗️ |   |NO❗️ |


### Legend

|  Symbol  |  Meaning  |
|:--------:|-----------|
|    🛑    | Function can modify state |
|    💵    | Function is payable |

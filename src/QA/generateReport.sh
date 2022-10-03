#!/usr/bin/env sh

# Checkout https://github.com/ConsenSys/surya
# ubuntu to install graphviz use `sudo apt-get install graphviz`

surya mdreport report_PWN.md ../PWN.sol
surya mdreport report_PWNVault.md ../PWNVault.sol
surya mdreport report_PWNDeed.md ../PWNDeed.sol

surya graph ../**.sol | dot -Tpng > PWNFlow.png

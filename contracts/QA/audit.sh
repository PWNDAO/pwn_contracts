#!/usr/bin/env sh

surya mdreport report_PWN.md ../PWN.sol
surya mdreport report_PWNVault.md ../PWNVault.sol
surya mdreport report_PWNDeed.md ../PWNDeed.sol

surya graph ../**.sol | dot -Tpng > PWNFlow.png

// SPDX-License-Identifier: WTFPL
pragma solidity 0.6.12;

import "../SodaVault.sol";

// Owned by Timelock
contract sdUSDUSDCLPVault is SodaVault {

    constructor (
        SodaMaster _sodaMaster,
        IStrategy _createMoreSoda
    ) SodaVault(_sodaMaster, "Soda sdUSD-USDC-UNI-V2-LP Vault", "vsdUSD-USDC-UNI-V2-LP") public  {
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = _createMoreSoda;
        setStrategies(strategies);
    }
}

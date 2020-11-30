// SPDX-License-Identifier: WTFPL
pragma solidity 0.6.12;

import "../SodaVault.sol";

// Owned by Timelock
contract USDTVault is SodaVault {

    constructor (
        SodaMaster _sodaMaster,
        IStrategy _useAAve
    ) SodaVault(_sodaMaster, "Soda USDT Vault", "vUSDT") public  {
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = _useAAve;
        setStrategies(strategies);
    }
}

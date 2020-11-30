// SPDX-License-Identifier: WTFPL
pragma solidity 0.6.12;

import "../GovernableSodaVault.sol";

// Owned by Timelock
contract SodaSodaVault is GovernableSodaVault {

    constructor (
        SodaMaster _sodaMaster,
        IStrategy _shareRevenue
    ) GovernableSodaVault(_sodaMaster, "Soda SODA Vault", "vSODA") public  {
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = _shareRevenue;
        setStrategies(strategies);
    }
}

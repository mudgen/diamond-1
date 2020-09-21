// SPDX-License-Identifier: MIT
pragma solidity ^0.7.1;
pragma experimental ABIEncoderV2;

/******************************************************************************\
* Author: Nick Mudge
*
* Implementation of Diamond facet.
/******************************************************************************/

import "./LibDiamondStorage.sol";
import "../interfaces/IDiamondCut.sol";

library LibDiamondCut {
    event DiamondCut(IDiamondCut.Facet[] _diamondCut, address _init, bytes _calldata);

    // Non-standard internal function version of diamondCut
    // This code is almost the same as externalCut, except it is using
    // Facet[] memory _diamondCut' instead of Facet[] calldata _diamondCut'
    // and it DOES issue the DiamondCut event
    // The code is duplicated to prevent copying calldata to memory which
    // causes an error for a two dimensional array.
    function diamondCut(IDiamondCut.Facet[] memory _diamondCut) internal {
        LibDiamondStorage.DiamondStorage storage ds = LibDiamondStorage.diamondStorage();
        uint256 selectorCount = ds.selectors.length;
        for (uint256 facetIndex; facetIndex < _diamondCut.length; facetIndex++) {
            address newFacetAddress = _diamondCut[facetIndex].facetAddress;
            // adding or replacing functions
            if (newFacetAddress != address(0)) {
                hasContractCode(newFacetAddress, "LibDiamondCut: facet has no code");
                // add and replace selectors
                for (uint256 selectorIndex; selectorIndex < _diamondCut[facetIndex].functionSelectors.length; selectorIndex++) {
                    bytes4 selector = _diamondCut[facetIndex].functionSelectors[selectorIndex];
                    address oldFacetAddress = ds.facetAddressAndSelectorPosition[selector].facetAddress;
                    // add
                    if (oldFacetAddress == address(0)) {
                        ds.facetAddressAndSelectorPosition[selector] = LibDiamondStorage.FacetAddressAndSelectorPosition(
                            newFacetAddress,
                            uint16(selectorCount)
                        );
                        ds.selectors.push(selector);
                        selectorCount++;
                    } else {
                        // replace
                        require(oldFacetAddress != address(this), "LibDiamondCut: Can't remove immutable function");
                        if (oldFacetAddress != newFacetAddress) {
                            // replace old facet address
                            ds.facetAddressAndSelectorPosition[selector].facetAddress = newFacetAddress;
                        }
                    }
                }
            } else {
                // remove functions
                for (uint256 selectorIndex; selectorIndex < _diamondCut[facetIndex].functionSelectors.length; selectorIndex++) {
                    bytes4 selector = _diamondCut[facetIndex].functionSelectors[selectorIndex];
                    LibDiamondStorage.FacetAddressAndSelectorPosition memory oldFacetAddressAndSelectorPosition = ds
                        .facetAddressAndSelectorPosition[selector];
                    // if selector already does not exist then do nothing
                    if (oldFacetAddressAndSelectorPosition.facetAddress == address(0)) {
                        continue;
                    }
                    require(oldFacetAddressAndSelectorPosition.facetAddress != address(this), "LibDiamondCut: Can't remove immutable function.");
                    bytes4 lastSelector = ds.selectors[selectorCount - 1];
                    // replace selector with last selector
                    if (oldFacetAddressAndSelectorPosition.selectorPosition != selectorCount - 1) {
                        ds.selectors[oldFacetAddressAndSelectorPosition.selectorPosition] = lastSelector;
                        ds.facetAddressAndSelectorPosition[lastSelector].selectorPosition = oldFacetAddressAndSelectorPosition.selectorPosition;
                    }
                    // delete last selector
                    ds.selectors.pop();
                    delete ds.facetAddressAndSelectorPosition[selector];
                    selectorCount--;
                }
            }
        }
        emit DiamondCut(_diamondCut, address(0), new bytes(0));
    }

    function hasContractCode(address _contract, string memory _errorMessage) internal view {
        uint256 contractSize;
        assembly {
            contractSize := extcodesize(_contract)
        }
        require(contractSize > 0, _errorMessage);
    }
}

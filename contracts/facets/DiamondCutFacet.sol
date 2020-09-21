// SPDX-License-Identifier: MIT
pragma solidity ^0.7.1;
pragma experimental ABIEncoderV2;

/******************************************************************************\
* Author: Nick Mudge <nick@perfectabstractions.com> (https://twitter.com/mudgen)
/******************************************************************************/

import "../interfaces/IDiamondCut.sol";
import "../libraries/LibDiamondStorage.sol";
import "../libraries/LibDiamondCut.sol";

contract DiamondCutFacet is IDiamondCut {
    // Standard diamondCut external function
    /// @notice Add/replace/remove any number of functions and optionally execute
    ///         a function with delegatecall
    /// @param _diamondCut Contains the facet addresses and function selectors
    /// @param _init The address of the contract or facet to execute _calldata
    /// @param _calldata A function call, including function selector and arguments
    ///                  _calldata is executed with delegatecall on _init
    function diamondCut(
        Facet[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external override {
        externalCut(_diamondCut);
        emit DiamondCut(_diamondCut, _init, _calldata);
        if (_init == address(0)) {
            require(_calldata.length == 0, "DiamondCutFacet: _init is address(0) but_calldata is not empty");
        } else {
            require(_calldata.length > 0, "DiamondCutFacet: _calldata is empty but _init is not address(0)");
            if (_init != address(this)) {
                LibDiamondCut.hasContractCode(_init, "DiamondCutFacet: _init address has no code");
            }
            (bool success, bytes memory error) = _init.delegatecall(_calldata);
            if (!success) {
                if (error.length > 0) {
                    // bubble up the error
                    revert(string(error));
                } else {
                    revert("DiamondCutFacet: _init function reverted");
                }
            }
        }
    }

    // diamondCut helper function
    // This code is almost the same as the internal diamondCut function,
    // except it is using 'Facets[] calldata _diamondCut' instead of
    // 'Facet[] memory _diamondCut', and it does not issue the DiamondCut event.
    // The code is duplicated to prevent copying calldata to memory which
    // causes a Solidity error for two dimensional arrays.
    function externalCut(Facet[] calldata _diamondCut) internal {
        LibDiamondStorage.DiamondStorage storage ds = LibDiamondStorage.diamondStorage();
        require(msg.sender == ds.contractOwner, "Must own the contract.");
        uint256 selectorCount = ds.selectors.length;
        for (uint256 facetIndex; facetIndex < _diamondCut.length; facetIndex++) {
            address newFacetAddress = _diamondCut[facetIndex].facetAddress;
            // adding or replacing functions
            if (newFacetAddress != address(0)) {
                LibDiamondCut.hasContractCode(newFacetAddress, "LibDiamondCut: facet has no code");
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
                        require(oldFacetAddress != address(this), "DiamondCutFacet: Can't replace immutable function");
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
                    require(oldFacetAddressAndSelectorPosition.facetAddress != address(this), "DiamondCutFacet: Can't remove immutable function");
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
    }
}

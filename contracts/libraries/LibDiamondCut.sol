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
    event DiamondCut(IDiamondCut.FacetCut[] _diamondCut, address _init, bytes _calldata);

    // Internal function version of diamondCut
    // This code is almost the same as the external diamondCut,
    // except it is using 'Facet[] memory _diamondCut' instead of
    // 'Facet[] calldata _diamondCut'.
    // The code is duplicated to prevent copying calldata to memory which
    // causes an error for a two dimensional array.
    function diamondCut(
        IDiamondCut.FacetCut[] memory _diamondCut,
        address _init,
        bytes memory _calldata
    ) internal {
        LibDiamondStorage.DiamondStorage storage ds = LibDiamondStorage.diamondStorage();
        uint256 selectorCount = ds.selectors.length;
        for (uint256 facetIndex; facetIndex < _diamondCut.length; facetIndex++) {
            selectorCount = addReplaceRemoveFacetSelectors(
                selectorCount,
                _diamondCut[facetIndex].facetAddress,
                _diamondCut[facetIndex].action,
                _diamondCut[facetIndex].functionSelectors
            );
        }
        emit DiamondCut(_diamondCut, _init, _calldata);
        initializeDiamondCut(_init, _calldata);
    }

    function addReplaceRemoveFacetSelectors(
        uint256 _selectorCount,
        address _newFacetAddress,
        IDiamondCut.FacetCutAction _action,
        bytes4[] memory _selectors
    ) internal returns (uint256) {
        LibDiamondStorage.DiamondStorage storage ds = LibDiamondStorage.diamondStorage();
        require(_selectors.length > 0, "LibDiamondCut: No selectors in facet to cut");
        // add or replace functions
        if (_newFacetAddress != address(0)) {
            hasContractCode(_newFacetAddress, "LibDiamondCut: facet has no code");
            for (uint256 selectorIndex; selectorIndex < _selectors.length; selectorIndex++) {
                bytes4 selector = _selectors[selectorIndex];
                address oldFacetAddress = ds.facetAddressAndSelectorPosition[selector].facetAddress;
                // add
                if (_action == IDiamondCut.FacetCutAction.Add) {
                    require(oldFacetAddress == address(0), "LibDiamondCut: Can't add function that already exists");
                    ds.facetAddressAndSelectorPosition[selector] = LibDiamondStorage.FacetAddressAndSelectorPosition(
                        _newFacetAddress,
                        uint16(_selectorCount)
                    );
                    ds.selectors.push(selector);
                    _selectorCount++;
                } else if (_action == IDiamondCut.FacetCutAction.Replace) {
                    // replace
                    // only useful if immutable functions exist
                    require(oldFacetAddress != address(this), "LibDiamondCut: Can't replace immutable function");
                    require(oldFacetAddress != _newFacetAddress, "LibDiamondCut: Can't replace function with same function");
                    require(oldFacetAddress != address(0), "LibDiamondCut: Can't replace function that doesn't exist");
                    // replace old facet address
                    ds.facetAddressAndSelectorPosition[selector].facetAddress = _newFacetAddress;
                } else {
                    revert("LibDiamondCut: Incorrect FacetCutAction");
                }
            }
        } else {
            require(_action == IDiamondCut.FacetCutAction.Remove, "LibDiamondCut: action not set to FacetCutAction.Remove");
            // remove functions
            for (uint256 selectorIndex; selectorIndex < _selectors.length; selectorIndex++) {
                bytes4 selector = _selectors[selectorIndex];
                LibDiamondStorage.FacetAddressAndSelectorPosition memory oldFacetAddressAndSelectorPosition = ds
                    .facetAddressAndSelectorPosition[selector];
                require(oldFacetAddressAndSelectorPosition.facetAddress != address(0), "LibDiamondCut: Can't remove function that doesn't exist");
                // only useful if immutable functions exist
                require(oldFacetAddressAndSelectorPosition.facetAddress != address(this), "LibDiamondCut: Can't remove immutable function.");
                // replace selector with last selector
                if (oldFacetAddressAndSelectorPosition.selectorPosition != _selectorCount - 1) {
                    bytes4 lastSelector = ds.selectors[_selectorCount - 1];
                    ds.selectors[oldFacetAddressAndSelectorPosition.selectorPosition] = lastSelector;
                    ds.facetAddressAndSelectorPosition[lastSelector].selectorPosition = oldFacetAddressAndSelectorPosition.selectorPosition;
                }
                // delete last selector
                ds.selectors.pop();
                delete ds.facetAddressAndSelectorPosition[selector];
                _selectorCount--;
            }
        }
        return _selectorCount;
    }

    function initializeDiamondCut(address _init, bytes memory _calldata) internal {
        if (_init == address(0)) {
            require(_calldata.length == 0, "LibDiamondCut: _init is address(0) but_calldata is not empty");
        } else {
            require(_calldata.length > 0, "LibDiamondCut: _calldata is empty but _init is not address(0)");
            if (_init != address(this)) {
                LibDiamondCut.hasContractCode(_init, "LibDiamondCut: _init address has no code");
            }
            (bool success, bytes memory error) = _init.delegatecall(_calldata);
            if (!success) {
                if (error.length > 0) {
                    // bubble up the error
                    revert(string(error));
                } else {
                    revert("LibDiamondCut: _init function reverted");
                }
            }
        }
    }

    function hasContractCode(address _contract, string memory _errorMessage) internal view {
        uint256 contractSize;
        assembly {
            contractSize := extcodesize(_contract)
        }
        require(contractSize > 0, _errorMessage);
    }
}

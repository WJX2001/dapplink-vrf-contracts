// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "./IBLSApkRegistry.sol";


interface IDappLinkVRFManager {
  function requestRandomWords(uint256 _requestId, uint256 _numWords) external;
  function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords, bytes32 msgHash, uint256 referenceBlockNumber, IBLSApkRegistry.VrfNoSignerAndSignature memory params) external;
  function getRequestStatus(uint256 _requestId) external view returns (bool fulfilled, uint256[] memory randomWords);
  function setDappLink(address _dappLinkAddress) external;
}
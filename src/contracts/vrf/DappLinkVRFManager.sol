// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./DappLinkVRFStorage.sol";
// import "../interface/IDappLinkVRFManager.sol";
import "../../interface/IDappLinkVRFManager.sol";

/* 
    工作流程：
    1. 用户调用 requestRandomWords(requestId,numWords)
    2. 合约记录请求，发出 RequestSent 事件
    3. 链下服务监听事件，生成随机数 本地的 dapplinkvrf项目 监听这个事件，并生成随机数
    4. DappLink 地址调用 fulfillRandomWords(requestId,randomWords)，验证调用者，设置fulfilled = true 存储随机数
    5. 查询 getRequestStatus 即可

*/

contract DappLinkVRF is
    Initializable,
    OwnableUpgradeable,
    DappLinkVRFStorage,
    IDappLinkVRFManager
{
    event RequestSent(uint256 requestId, uint256 _numWords, address current);

    event FillRandomWords(uint256 requestId, uint256[] randomWords);

    modifier onlyDappLink() {
        require(msg.sender == dappLinkAddress, "DappLinkVRF.onlyDappLink");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address initialOwner,
        address _dappLinkAddress,
        address _blsRegistry
    ) public initializer {
        __Ownable_init(initialOwner);
        blsRegistry = IBLSApkRegistry(_blsRegistry);
        dappLinkAddress = _dappLinkAddress;
    }

    function requestRandomWords(
        uint256 _requestId,
        uint256 _numWords
    ) external onlyOwner {
        requestMapping[_requestId] = RequestStatus({
            randomWords: new uint256[](0),
            fulfilled: false
        });
        requestIds.push(_requestId);
        lastRequestId = _requestId;
        emit RequestSent(_requestId, _numWords, address(this));
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords,
        bytes32 msgHash,
        uint256 referenceBlockNumber,
        IBLSApkRegistry.VrfNoSignerAndSignature memory params
    ) external onlyDappLink {
        // BLS 集成验签
        blsRegistry.checkSignatures(msgHash, referenceBlockNumber, params);

        requestMapping[_requestId] = RequestStatus({
            fulfilled: true,
            randomWords: _randomWords
        });
        emit FillRandomWords(_requestId, _randomWords);
    }

    function getRequestStatus(
        uint256 _requestId
    ) external view returns (bool fulfilled, uint256[] memory randomWords) {
        return (
            requestMapping[_requestId].fulfilled,
            requestMapping[_requestId].randomWords
        );
    }

    function setDappLink(address _dappLinkAddress) external onlyOwner {
        dappLinkAddress = _dappLinkAddress;
    }
}

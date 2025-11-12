// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../libraries/BN254.sol";

interface IBLSApkRegistry {
    // 签名验证参数
    // 用途：验证多个节点的聚合签名，同时记录哪些节点没参与签名
    struct VrfNoSignerAndSignature {
        BN254.G1Point[] nonSignerPubKeys; // 未签名者的公钥数组
        BN254.G2Point apkG2; // 聚合公钥 在 G2 群中
        BN254.G1Point sigma; // BLS 聚合签名 多个签名合并后的结果
        uint256 totalDappLinkStake; // 参与签名的 DappLink 质押总量
        uint256 totalBtcStake; // 参与签名的 BTC 质押总量
    }
    // 聚合公钥 更新记录
    // 用途：跟踪聚合公钥的历史变化 （当节点加入/退出时）
    struct ApkUpdate {
        bytes24 apkHash; // 聚合公钥的哈希值
        uint32 updateBlockNumber; // 本次更新的区块号
        uint32 nextUpdateBlockNumber; // 下次更新的区块号
    }

    // 公钥注册参数
    // 用途：节点注册时提供的公钥信息
    struct PubkeyRegistrationParams {
        BN254.G1Point pubkeyRegistrationSignature; // 注册签名 证明拥有私钥
        BN254.G1Point pubkeyG1; // G1 群中的公钥
        BN254.G2Point pubkeyG2; // G2 群中的公钥
    }

    // 质押总量
    // 用途：记录参与签名的节点的质押总量（用于权重计算）
    struct StakeTotals {
        uint256 totalDappLinkStake;
        uint256 totalBtcStake;
    }

    event NewPubkeyRegistration(address indexed operator, BN254.G1Point pubkeyG1, BN254.G2Point pubkeyG2);

    event OperatorAdded(address operator, bytes32 operatorId);

    event OperatorRemoved(address operator, bytes32 operatorId);

    // 运营商注册/注销
    // 作用：注册或者注销一个验证节点
    function registerOperator(address operator) external;
    function deregisterOperator(address operator) external;

    // 注册 BLS 公钥
    /**
     * 作用：
     * 1. 节点提交 G1 和 G2 群中的公钥
     * 2. 提供签名证明拥有对应私钥
     * 3. 返回操作者 ID 
     */
    function registerBLSPublicKey(
        address operator,
        PubkeyRegistrationParams calldata params,
        BN254.G1Point memory msgHash
    ) external returns (bytes32);

    // 验证签名（最核心）
    /*
      核心流程：
        1. 输入消息哈希
            ↓
        2. 输入聚合签名 (sigma)
             ↓
        3. 输入聚合公钥 (apkG2)
             ↓
        4. 提供未签名者列表
             ↓
        5. 使用 BN254 配对运算验证
             ↓
        6. 返回参与签名的质押总量 
            */

    function checkSignatures(bytes32 msgHash, uint256 referenceBlockNumber, VrfNoSignerAndSignature memory params) external view returns (StakeTotals memory, bytes32);
    // 查询公钥 查询某个节点注册的公钥
    function getRegisteredPubkey(address operator) external view returns (BN254.G1Point memory, bytes32);
    // 白名单管理 管理哪些地址可以注册为验证节点
    function addOrRemoveBlsRegisterWhitelist(address operator, bool isAdd) external;

    function getPubkeyRegMessageHash(address operator) external view returns (BN254.G1Point memory);
}

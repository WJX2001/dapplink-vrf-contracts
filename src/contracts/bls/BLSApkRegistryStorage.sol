// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
// import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {BN254} from "../../libraries/BN254.sol";
import {IBLSApkRegistry} from "../../interface/IBLSApkRegistry.sol";

abstract contract BLSApkRegistryStorage is Initializable, IBLSApkRegistry {
    bytes32 internal constant ZERO_PK_HASH =
        hex"ad3228b676f7d3cd4284a5443f17f1962b36e491b30a40b2405849e597ba5fb5";
    /**
     * @notice  注册 BLS 公钥时使用的 EIP-712 结构体类型哈希，用途如下：
     * 定义固定的签名消息格式:BN254PubkeyRegistration(address operator)
     * 在 getPubkeyRegMessageHash 中，它与操作者地址一起通过 _hashTypedDataV4 生成最终待签名的消息
     * 节点必须对这个特定消息做 BLS 签名，链上才能验证其确实拥有对应私钥。
     * TODO: 它确保 注册的是谁的语意明确、不可被恶意篡改，并与 EIP-712 域一起构成唯一的签名挑战
     */
    bytes32 public constant PUBKEY_REGISTRATION_TYPEHASH =
        keccak256("BN254PubkeyRegistration(address operator)");

    address public whitelistManager;
    address public vrfManagerAddress;

    mapping(address => bytes32) public operatorToPubkeyHash; 
    mapping(bytes32 => address) public pubkeyHashToOperator; 
    mapping(address => BN254.G1Point) public operatorToPubkey; // 记录每个节点的公钥 G1群

    BN254.G1Point public currentApk; // 类型 G1Point 聚合公钥 所有节点公钥的和
    ApkUpdate[] public apkHistory; // 聚合公钥的历史记录 支持历史验证

    mapping(address => bool) public blsRegisterWhitelist; // 控制谁可以注册公钥
}

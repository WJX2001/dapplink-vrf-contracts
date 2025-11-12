// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
// import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../../libraries/BN254.sol";
import "../../interface/IBLSApkRegistry.sol";
import "./BLSApkRegistryStorage.sol";

contract BLSApkRegistry is
    Initializable,
    OwnableUpgradeable,
    IBLSApkRegistry,
    BLSApkRegistryStorage,
    EIP712
{
    using BN254 for BN254.G1Point;

    uint256 internal constant PAIRING_EQUALITY_CHECK_GAS = 120000;

    modifier onlyWhitelistManagerManager() {
        require(
            msg.sender == whitelistManager,
            "BLSApkRegistry.onlyRelayerManager: caller is not the relayer manager address"
        );
        _;
    }

    modifier onlyVrfManager() {
        require(
            msg.sender == vrfManagerAddress,
            "BLSApkRegistry.onlyRelayerManager: caller is not the relayer manager address"
        );
        _;
    }

    constructor() EIP712("BLSApkRegistry", "v0.0.1") {
        _disableInitializers();
    }

    function initialize(
        address _initialOwner,
        address _whitelistManager,
        address _vrfManagerAddress
    ) external initializer {
        _transferOwnership(_initialOwner);
        whitelistManager = _whitelistManager;
        vrfManagerAddress = _vrfManagerAddress;
        _initializeApk();
    }

    /**
     * @dev Registers an operator within the system.
     *
     * This function allows the Finality Relayer Manager to add an operator to the system.
     * The operator's public key is retrieved and used to update the associated proof (APK).
     *
     * @param operator The address of the operator to be registered.
     */
    function registerOperator(address operator) public onlyVrfManager {
        (BN254.G1Point memory pubkey, ) = getRegisteredPubkey(operator);

        _processApkUpdate(pubkey);

        emit OperatorAdded(operator, operatorToPubkeyHash[operator]);
    }

    function deregisterOperator(address operator) public onlyVrfManager {
        (BN254.G1Point memory pubkey, ) = getRegisteredPubkey(operator);

        _processApkUpdate(pubkey.negate());
        emit OperatorRemoved(operator, operatorToPubkeyHash[operator]);
    }

    // 节点想要参与签名 必须先注册公钥
    function registerBLSPublicKey(
        address operator,
        PubkeyRegistrationParams calldata params,
        BN254.G1Point calldata pubkeyRegistrationMessageHash
    ) external returns (bytes32) {
        require(
            // 只有白名单地址才能注册公钥
            blsRegisterWhitelist[msg.sender],
            "BLSApkRegistry.registerBLSPublicKey: this address have not permission to register bls key"
        );

        bytes32 pubkeyHash = BN254.hashG1Point(params.pubkeyG1);
        // 不能注册零公钥
        require(
            pubkeyHash != ZERO_PK_HASH,
            "BLSApkRegistry.registerBLSPublicKey: cannot register zero pubkey"
        );
        require(
            operatorToPubkeyHash[operator] == bytes32(0),
            "BLSApkRegistry.registerBLSPublicKey: operator already registered pubkey"
        );

        require(
            pubkeyHashToOperator[pubkeyHash] == address(0),
            "BLSApkRegistry.registerBLSPublicKey: public key already registered"
        );

        // 公钥验证 这段代码验证节点确实拥有声称的私钥
        uint256 gamma = uint256(
            keccak256(
                abi.encodePacked(
                    params.pubkeyRegistrationSignature.X,
                    params.pubkeyRegistrationSignature.Y,
                    params.pubkeyG1.X,
                    params.pubkeyG1.Y,
                    params.pubkeyG2.X,
                    params.pubkeyG2.Y,
                    pubkeyRegistrationMessageHash.X,
                    pubkeyRegistrationMessageHash.Y
                )
            )
        ) % BN254.FR_MODULUS;

        /**
 * BLS 签名的基本原理 
 * 私钥： sk 一个标量
 * 公钥： 
 *  - G1 上的公钥 pk_G1 = sk * G1 (G1 是G1 群的生成元)
 *  - G2 上的公钥 pk_G2 = sk * G2 (G2 是 G2 群的生成元)
 * 
 * 签名：signature = sk * H(m)（H(m) 是消息哈希映射到 G1 上的点）
 * 
 * e(signature + pk·γ, -G2) · e(H(msg) + G1·γ, pk_G2) = 1

等价于验证：
e(signature, G2) = e(H(msg), pk_G2)

gamma 的目的：防止攻击者提交伪造的公钥对。
 */
        require(
            BN254.pairing(
                // 第一步 验证签名
                // params.pubkeyRegistrationSignature：签名（应该等于 sk * H(m)）
                // params.pubkeyG1.scalar_mul(gamma): 公钥乘以 gamma (γ * sk * G1)
                // 合在一起：signature + γ * pk_G1 = sk * H(m) + γ * sk * G1
                params.pubkeyRegistrationSignature.plus(
                    params.pubkeyG1.scalar_mul(gamma)
                ),
                // 这是 G2 群生成元的负值：-G2
                BN254.negGeneratorG2(),
                // 第二步：验证消息和公钥
                // pubkeyRegistrationMessageHash：消息哈希映射到 G1 上的点 H(m)
                // BN254.generatorG1().scalar_mul(gamma)：生成元乘以 gamma（γ * G1）
                // 合在一起：H(m) + γ * G1
                pubkeyRegistrationMessageHash.plus(
                    BN254.generatorG1().scalar_mul(gamma)
                ),
                // 这是 G2 上的公钥 pk_G2 = sk * G2
                params.pubkeyG2
            ),
            /**
             * 如果签名和密钥都正确，配对验证应该满足
             * e(signature + γ * pk_G1, -G2) * e(H(m) + γ * G1, pk_G2) = 1
             * 展开： e(sk * H(m) + γ * sk * G1, -G2) * e(H(m) + γ * G1, sk * G2) = 1
             * 利用配对的双线性性质：e(a*P, Q) = e(P, a*Q) = e(P, Q)^a
             * e(sk * H(m), -G2) * e(γ * sk * G1, -G2) * e(H(m), sk * G2) * e(γ * G1, sk * G2) = 1
             * e(H(m), -sk * G2) * e(G1, -γ * sk * G2) * e(H(m), sk * G2) * e(G1, γ * sk * G2) = 1
             * 注意到第一项和第三项互为倒数（因为一个是负的）：
             * e(H(m), -sk * G2) * e(H(m), sk * G2) = 1
             * 第二项和第四项也互为倒数：
             * e(G1, -γ * sk * G2) * e(G1, γ * sk * G2) = 1
             */
            "BLSApkRegistry.registerBLSPublicKey: either the G1 signature is wrong, or G1 and G2 private key do not match"
        );

        operatorToPubkey[operator] = params.pubkeyG1;
        operatorToPubkeyHash[operator] = pubkeyHash;
        pubkeyHashToOperator[pubkeyHash] = operator;

        emit NewPubkeyRegistration(operator, params.pubkeyG1, params.pubkeyG2);

        return pubkeyHash;
    }
    // TODO: 签名验证流程（核心部分）
    function checkSignatures(
        /** 
         * 待验证的消息哈希。
         * 外部调用方先把业务消息（例如 VRF 结果或者任务内容）做哈希，这个哈希值就是 BLS 聚合签名要覆盖的对象。
         * 合约会基于它生成 G1 上的消息点，并用来和聚合公钥、聚合签名一起做配对验证
         * */
        bytes32 msgHash, 
        /**
         * 参考区块号
         * 表示这次验证要针对哪个历史快照来判定签名人集合。
         * 合约内部会用它与 apkHistory 做对比，确保调用者提供的未签名者列表、聚合公钥等数据匹配指定区块之前的状态
         * 如果传入的区块号不早于当前区块，会直接拒绝，避免使用未来状态或未经确认的数据
         */
        uint256 referenceBlockNumber,
        VrfNoSignerAndSignature memory params
    ) public view returns (StakeTotals memory, bytes32) {
        require(
            referenceBlockNumber < uint32(block.number),
            "BLSSignatureChecker.checkSignatures: invalid reference block"
        );
        BN254.G1Point memory signerApk = BN254.G1Point(0, 0);
        bytes32[] memory nonSignersPubkeyHashes;
        if (params.nonSignerPubKeys.length > 0) {
            // 有未签名者
            nonSignersPubkeyHashes = new bytes32[](
                params.nonSignerPubKeys.length
            );
            // 减去未签名者
            for (uint256 j = 0; j < params.nonSignerPubKeys.length; j++) {
                nonSignersPubkeyHashes[j] = params
                    .nonSignerPubKeys[j]
                    .hashG1Point();
                signerApk = currentApk.plus(
                    params.nonSignerPubKeys[j].negate()
                );
            }
        } else {
            // 所有人都签名了
            signerApk = currentApk;
        }
        (
            bool pairingSuccessful,
            bool signatureIsValid
        ) = trySignatureAndApkVerification(
                msgHash,
                signerApk,
                params.apkG2,
                params.sigma
            );

        require(
            pairingSuccessful,
            "BLSSignatureChecker.checkSignatures: pairing precompile call failed"
        );
        require(
            signatureIsValid,
            "BLSSignatureChecker.checkSignatures: signature is invalid"
        );
        // 返回质押信息，记录哪些人签名了，以及他们的质押总量
        bytes32 signatoryRecordHash = keccak256(
            abi.encodePacked(referenceBlockNumber, nonSignersPubkeyHashes)
        );

        StakeTotals memory stakeTotals = StakeTotals({
            totalDappLinkStake: params.totalDappLinkStake,
            totalBtcStake: params.totalBtcStake
        });

        return (stakeTotals, signatoryRecordHash);
    }

    function addOrRemoveBlsRegisterWhitelist(
        address register,
        bool isAdd
    ) external onlyWhitelistManagerManager {
        require(
            register != address(0),
            "BLSApkRegistry.addOrRemoverBlsRegisterWhitelist: operator address is zero"
        );
        blsRegisterWhitelist[register] = isAdd;
    }
    /** 
     * 核心配对检查
     * 验证等式：
        e(σ + apk·γ, -G2) · e(H(msg) + G1·γ, apk_G2) = 1
        其中：
- σ (sigma)：聚合签名
- apk：签名者的聚合公钥（G1）
- apk_G2：聚合公钥（G2）
- γ (gamma)：随机挑战值（防重放）
- H(msg)：消息哈希映射到G1

    数学基础：
        签名：σ = sk · H(msg)  （私钥乘以消息哈希）
        公钥：pk = sk · G2      （私钥乘以G2生成元）

        验证：
        e(σ, G2) = e(sk·H(msg), G2)
                = e(H(msg), sk·G2)
                = e(H(msg), pk)  ✅ 匹配！
     */
    function trySignatureAndApkVerification(
        bytes32 msgHash,
        BN254.G1Point memory apk,
        BN254.G2Point memory apkG2,
        BN254.G1Point memory sigma
    ) public view returns (bool pairingSuccessful, bool siganatureIsValid) {
        uint256 gamma = uint256(
            keccak256(
                abi.encodePacked(
                    msgHash,
                    apk.X,
                    apk.Y,
                    apkG2.X[0],
                    apkG2.X[1],
                    apkG2.Y[0],
                    apkG2.Y[1],
                    sigma.X,
                    sigma.Y
                )
            )
        ) % BN254.FR_MODULUS;
            // e(σ + apk·γ, -G2) · e(H(msg) + G1·γ, apk_G2) = 1
            /** 
             * 标准 BLS 验证：
             *  - e(σ, G2) == e(H(msg), apk_G2)
             *  - σ: 聚合签名
             *  - H(msg): 把消息哈希映射到 G1 群的点 
             *  - apk_G2 聚合公钥 在G2群
             *  - G2: G2群的基点
             * 
             * 如果 σ = sk * H(msg) apk_G2 = sk * G2
             * e(σ, G2) = e(sk * H(msg),G2) = e(H(msg),sk*G2) = e(H(msg),apk_G2)
            */
           (pairingSuccessful, siganatureIsValid) = BN254.safePairing(
            sigma.plus(apk.scalar_mul(gamma)),
            BN254.negGeneratorG2(),
            BN254.hashToG1(msgHash).plus(BN254.generatorG1().scalar_mul(gamma)),
            apkG2,
            PAIRING_EQUALITY_CHECK_GAS
        );
    }

    /**
     *  聚合公钥（APK）管理
     *  当节点注册/注销时，需要更新聚合公钥
     */

    function _processApkUpdate(BN254.G1Point memory point) internal {
        // 声明新的聚合公钥 类型为 G1 点
        BN254.G1Point memory newApk;
        // 读取聚合公钥历史数组 apkHistory 的当前长度，用于后续逻辑判断
        uint256 historyLength = apkHistory.length;
        // 确保历史数组已经初始化，反之未建立初始聚合公钥 直接 revert 
        require(
            historyLength != 0,
            "BLSApkRegistry._processApkUpdate: quorum does not exist"
        );
        // 将传入的点 point 加到当前聚合公钥 currentApk 上。加正公钥表示节点加入，传入负公钥则等价于减去原公钥
        newApk = currentApk.plus(point);
        // 更新当前聚合公钥 currentApk 为新的聚合公钥 newApk
        currentApk = newApk;
        // 对新的聚合公钥做哈希，并截断为 bytes24, 用于存入历史记录。哈希而不是直接存点可以节省存储空间
        bytes24 newApkHash = bytes24(BN254.hashG1Point(newApk));
        // 取历史数组中最后一条记录的引用 lastUpdate 方便更新或比较
        ApkUpdate storage lastUpdate = apkHistory[historyLength - 1];
        // 判断当前区块号是否和最后一次更新的updateBlockNumber 相同，处理同一区块内的多次更新
        if (lastUpdate.updateBlockNumber == uint32(block.number)) {
            lastUpdate.apkHash = newApkHash;
        } else {
            lastUpdate.nextUpdateBlockNumber = uint32(block.number);
            apkHistory.push(
                ApkUpdate({
                    apkHash: newApkHash,
                    updateBlockNumber: uint32(block.number),
                    nextUpdateBlockNumber: 0
                })
            );
        }
    }

    function getRegisteredPubkey(
        address operator
    ) public view returns (BN254.G1Point memory, bytes32) {
        BN254.G1Point memory pubkey = operatorToPubkey[operator];
        bytes32 pubkeyHash = operatorToPubkeyHash[operator];

        require(
            pubkeyHash != bytes32(0),
            "BLSApkRegistry.getRegisteredPubkey: operator is not registered"
        );

        return (pubkey, pubkeyHash);
    }

    function getPubkeyRegMessageHash(
        address operator
    ) public view returns (BN254.G1Point memory) {
        return
            BN254.hashToG1(
                _hashTypedDataV4(
                    keccak256(
                        abi.encode(PUBKEY_REGISTRATION_TYPEHASH, operator)
                    )
                )
            );
    }

    function _initializeApk() internal {
        require(
            apkHistory.length == 0,
            "BLSApkRegistry.initializeApk: apk already exists"
        );
        apkHistory.push(
            ApkUpdate({
                apkHash: bytes24(0),
                updateBlockNumber: uint32(block.number),
                nextUpdateBlockNumber: 0
            })
        );
    }

    function getPubkeyHash(address operator) public view returns (bytes32) {
        return operatorToPubkeyHash[operator];
    }
}

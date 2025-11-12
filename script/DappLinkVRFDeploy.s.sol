// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Vm.sol";
import {Script, console} from "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../src/utils/EmptyContract.sol";

import "../src/contracts/vrf/DappLinkVRFManager.sol";
import "../src/contracts/DappLinkVRFFactory.sol";
import "../src/contracts/bls/BLSApkRegistry.sol";

// forge script ./script/DappLinkVRFDepoly.s.sol --rpc-url https://eth-holesky.g.alchemy.com/v2/BvSZ5ZfdIwB-5SDXMz8PfGcbICYQqwrl --private-key $PrivateKey --broadcast
contract DappLinkVRFDepolyScript is Script {
    EmptyContract public emptyContract;
    ProxyAdmin public blsApkRegistryProxyAdmin;

    BLSApkRegistry public blsApkRegistry;
    BLSApkRegistry public blsApkRegistryImplementation;

    function run() external {
        // 开始广播，告诉 foundry 要上链了
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast();

        /**
         * 升级代理的常用套路：先部署空实现，再替换成真合约
         * 脚本希望最终把 BLSApkRegistry 这个合约部署成可升级的形式，所以才用了常见的升级代理流程
         * 1. 部署一个几乎没功能的空合约
         * 2. 用它来初始化一个 TransparentUpgradeableProxy（透明升级代理）
         */
        emptyContract = new EmptyContract();

        TransparentUpgradeableProxy proxyBlsApkRegistry = new TransparentUpgradeableProxy(
                address(emptyContract), // 初始实现指向空合约
                deployerAddress, // 代理管理员
                "" // 初始化数据留空
            );
        
        blsApkRegistry = BLSApkRegistry(address(proxyBlsApkRegistry));
        // 代理创建后，脚本部署真正的逻辑合约 BLSApkRegistry 实现独立部署
        blsApkRegistryImplementation = new BLSApkRegistry();
        blsApkRegistryProxyAdmin = ProxyAdmin(
            getProxyAdminAddress(address(proxyBlsApkRegistry))
            // getProxyAdminAddress` 会从代理的 `ADMIN_SLOT` 读取管理员地址（Foundry 的 `vm.load` 作弊码提供读取任意存储槽的能力）。
        );

        // 用管理员的 upgradeAndCall 方法把代理真正升级到逻辑合约并执行初始化
        blsApkRegistryProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(blsApkRegistry)),
            address(blsApkRegistryImplementation),
            abi.encodeWithSelector(
                BLSApkRegistry.initialize.selector,
                deployerAddress,
                deployerAddress,
                deployerAddress
            )
        );
        // 这样代理指向了真正的 BLSApkRegistry，并且在升级时立即调用 initialize 设置权限
        // 此时已经拥有了一个可升级版本的 BLSApkRegistry

        // 部署 VRF 逻辑和工厂
        // DappLinkVRF 是核心逻辑合约
        // DappLinkVRFFactory 是用来生成代理实例的工厂合约
        DappLinkVRF dappLinkVRF = new DappLinkVRF();
        DappLinkVRFFactory dappLinkVRFFactory = new DappLinkVRFFactory();
        // 用工厂创建 VRF 代理
        address proxyDappLink = dappLinkVRFFactory.createProxy(
            address(dappLinkVRF), // VRF 逻辑合约地址
            msg.sender, // 代理的 owner (脚本运行时，msg.sender等于部署者地址)
            address(blsApkRegistry) // 关联的 BLS 注册表地址
        );

        console.log(
            "dapplink blsApkRegistry contract deployed at:",
            address(blsApkRegistry)
        );
        console.log(
            "dapplink base contract deployed at:",
            address(dappLinkVRF)
        );
        console.log(
            "DappLink Proxy Factory contract deployed at:",
            address(dappLinkVRFFactory)
        );
        console.log("DappLink Proxy contract deployed at:", proxyDappLink);
        /*
         * dapplink blsApkRegistry contract deployed at: 0x78Ea04E072C857C508999b391176e91487A6F27f
         * dapplink base contract deployed at: 0x5459028BA30E096Fc3A3748e52741625E12af44F
         * DappLink Proxy Factory contract deployed at: 0xEd3d1EAE2Ea3A8Fa11a490157afCf6051EA98E49
         * DappLink Proxy contract deployed at: 0xD7Aa231A3470668ac46ABFC63b46ddC81DF4727f
         */
        vm.stopBroadcast();
    }

    function getProxyAdminAddress(
        address proxy
    ) internal view returns (address) {
        address CHEATCODE_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
        Vm vm = Vm(CHEATCODE_ADDRESS);

        bytes32 adminSlot = vm.load(proxy, ERC1967Utils.ADMIN_SLOT);
        return address(uint160(uint256(adminSlot)));
    }
}

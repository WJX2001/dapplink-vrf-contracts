// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./DappLinkVRF.sol";
/* 
  1. 工厂模式（Factory Pattern）
  这是一个工厂合约，用于批量创建 DappLinkVRF 合约实例
   - 为每个用户/项目 快速创建独立的 VRF 可验证随机函数 合约实例
   - 降低部署成本
   - 统一管理合约创建流程

  2. 最小代理模式（EIP-1167）
  工作原理：
    2.1 Implementation（实现合约）：只部署一次完整的逻辑合约
    2.2 Clone 克隆/代理 每次通过工厂创建时，只部署一个极小的代理合约
    2.3 委托调用：代理合约将所有调用转发到合约实现
*/

contract DappLinkVRFFactory {
  event ProxyCreated(address mintProxyAddress);
  

  /**
   * 
   * @param implementation 实现合约的地址 DapplinkVRF 的主合约地址
   * @param dapplinkAddress  Dapplink 服务地址 有权限调用 fulfillRandomWords 的地址
   */  
  function createProxy(address implementation, address dapplinkAddress) external returns(address) {
    // 克隆合约
    address mintProxyAddress = Clones.clone(implementation);
    // 初始化 调用新创建代理的 initialize 函数，msg.sender 成为代理合约的 owner 设置 dapplinkAddress 作为随机数服务提供者
    DappLinkVRF(mintProxyAddress).initialize(msg.sender,dapplinkAddress);
    emit ProxyCreated(mintProxyAddress);
    return mintProxyAddress;
  } 
}
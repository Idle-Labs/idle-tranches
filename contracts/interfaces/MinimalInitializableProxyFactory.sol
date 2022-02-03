pragma solidity 0.8.10;

interface MinimalInitializableProxyFactory {
  event ProxyCreated(address indexed implementation, address proxy);
  function create(address target) external;
  function createAndCall(address target, string calldata initSignature, bytes calldata initData) external;
}
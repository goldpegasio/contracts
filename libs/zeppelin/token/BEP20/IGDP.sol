pragma solidity 0.4.25;
import './IBEP20.sol';

contract IGDP is IBEP20 {
  function burn(uint _amount) external;
}

pragma solidity 0.4.25;

import './libs/goldpegas/Auth.sol';
import './libs/goldpegas/MerkelProof.sol';
import './libs/zeppelin/math/SafeMath.sol';
import './libs/zeppelin/token/BEP20/IBEP20.sol';
import './libs/zeppelin/token/BEP20/IGDP.sol';

contract PrivateSale is Auth {
  using SafeMath for uint;
  struct User {
    address userAddress;
    uint[] amounts;
    uint totalUSDT;
    uint totalGDP;
  }

  IGDP public gdpToken;
  IBEP20 public usdtToken;

  uint[] public amounts = [0, 1e24, 1e24, 1e24, 1e24, 1e24, 1e24, 1e24, 1e24, 1e24, 1e24, 2e24, 2e24, 2e24, 2e24, 2e24, 3e24, 3e24, 3e24, 3e24, 3e24];
  uint[] public prices = [0, 30e15, 36e15, 42e15, 48e15, 54e15, 60e15, 66e15, 72e15, 78e15, 84e15, 90e15, 96e15, 102e15, 108e15, 114e15, 120e15, 126e15, 132e15, 138e15, 144e15];
  uint[] public sold = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
  uint public cap = 1e25;
  uint constant decimal18 = 1e18;
  uint public constant blocksPerRound = 144000;
  uint constant totalRound = 20;
  uint constant privateSaleAllocation = 35e24;
  address private usdtHolder;
  uint public roundStartBlock;
  bool public openSale;
  bool public whitelistOpened;
  uint public currentRound = 1;
  uint public totalUSDT;
  uint public totalGDP;
  bytes32 public rootHash;

  mapping (address => User) private users;

  event Bought(address indexed _user, uint _amount, uint _round, uint _timestamp);
  event Claimed(address indexed _user, uint _amount, uint _timestamp);
  event WhiteListUpdated(bool _open);
  event RoundUpdated(uint _currentRound, uint _roundStartBlock);

  constructor(
    address _mainAdmin,
    address _backupAdmin,
    address _usdtHolder,
    address _gdpToken,
    address _busdtToken
  ) public Auth(_mainAdmin, _backupAdmin) {
    usdtHolder = _usdtHolder;
    gdpToken = IGDP(_gdpToken);
    usdtToken = IBEP20(_busdtToken);
  }

  // OWNER FUNCTIONS

  function setRootHash(bytes32 _rootHash) onlyMainAdmin public {
    rootHash = _rootHash;
  }

  function setCap(uint _cap) onlyMainAdmin public {
    cap = _cap;
  }

  function startSale() onlyMainAdmin public {
    require(!openSale, 'GDP PrivateSale: sale already started!!!');
    openSale = true;
    roundStartBlock = block.number;
  }

  function updateWhiteList(bool _open) onlyMainAdmin public {
    whitelistOpened = _open;
    emit WhiteListUpdated(_open);
  }

  function finish() onlyMainAdmin public {
    require(openSale, 'GDP PrivateSale: sale is not opening or already stopped!!!');
    uint totalSold;
    for (uint i = 1; i <= totalRound; i++) {
      totalSold = totalSold.add(sold[i]);
    }
    openSale = false;
    gdpToken.burn(privateSaleAllocation.sub(totalSold));
  }

  function updateMainAdmin(address _newMainAdmin) onlyBackupAdmin public {
    require(_newMainAdmin != address(0), 'GDP PrivateSale: invalid mainAdmin address');
    mainAdmin = _newMainAdmin;
  }

  function updateBackupAdmin(address _newBackupAdmin) onlyBackupAdmin public {
    require(_newBackupAdmin != address(0), 'GDP PrivateSale: invalid backupAdmin address');
    backupAdmin = _newBackupAdmin;
  }

  function updateUsdtHolder(address _newUsdtHolder) onlyMainAdmin public {
    require(_newUsdtHolder != address(0), 'GDP PrivateSale: invalid usdtHolder address');
    usdtHolder = _newUsdtHolder;
  }

  function setToken(address _gdpToken) onlyMainAdmin public {
    require(_gdpToken != address(0), 'GDP PrivateSale: invalid token address');
    gdpToken = IGDP(_gdpToken);
  }

  // PUBLIC FUNCTIONS

  function checkWhitelist(address _address, bytes32[] _path) public view returns (bool) {
    bytes32 hash = keccak256(abi.encodePacked(_address));
    return MerkleProof.verify(_path, rootHash, hash);
  }

  function buyWhiteList(uint _usdtAmount, bytes32[] _path) public {
    require(openSale, 'GDP PrivateSale: sale is not open!!!');
    require(whitelistOpened, 'GDP PrivateSale: whitelist is not opened!!!');
    bytes32 hash = keccak256(abi.encodePacked(_msgSender()));
    require(MerkleProof.verify(_path, rootHash, hash), 'GDP PrivateSale: 400');
    _buy(_usdtAmount);
  }

  function buy(uint _usdtAmount) public {
    require(openSale, 'GDP PrivateSale: sale is not open!!!');
    require(!whitelistOpened, 'GDP PrivateSale: whitelist is opening!!!');
    _buy(_usdtAmount);
  }

  function claim() public {
    require(!openSale, 'GDP PrivateSale: sale is not finished!!!');
    User storage user = users[_msgSender()];
    uint userToken;
    for (uint i = 1; i <= totalRound; i++) {
      userToken = userToken.add(user.amounts[i]);
    }
    if (userToken > 0) {
      gdpToken.transfer(user.userAddress, userToken);
      user.totalGDP = 0;
      emit Claimed(user.userAddress, userToken, block.timestamp);
    }
  }

  function myInfo() public view returns (uint, uint) {
    User storage user = users[_msgSender()];
    if (user.userAddress == address(0)) {
      return (0, 0);
    }
    return (user.totalUSDT, user.totalGDP);
  }

  function updateRound() public {
    require(openSale, 'GDP PrivateSale: sale is not open!!!');
    uint blockPassed = block.number - roundStartBlock;
    if (blockPassed > blocksPerRound) {
      uint roundPassed = blockPassed / blocksPerRound;
      if (currentRound + roundPassed <= totalRound) {
        roundStartBlock += (roundPassed * blocksPerRound);
        currentRound += roundPassed;
        emit RoundUpdated(currentRound, roundStartBlock);
      }
    }
  }

  // PRIVATE FUNCTIONS

  function _buy(uint _usdtAmount) private {
    if (_usdtAmount <= 0) {
      return;
    }
    User storage user = users[_msgSender()];
    if (user.userAddress == address(0)) {
      user.userAddress = _msgSender();
      user.amounts = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
      user.totalGDP = 0;
      user.totalUSDT = 0;
    }
    _validateUserCap(user, _usdtAmount);
    updateRound();
    uint tokenLeftInRound = amounts[currentRound].sub(sold[currentRound]);
    require(tokenLeftInRound > 0, 'GDP PrivateSale: token sold!!!');
    uint usdtLeftInRound = tokenLeftInRound.mul(prices[currentRound]).div(decimal18);
    if (_usdtAmount < usdtLeftInRound) {
      uint willSaleTokenAmount = _usdtAmount.mul(decimal18).div(prices[currentRound]);
      updateStatistic(user, _usdtAmount, willSaleTokenAmount);
      usdtToken.transferFrom(_msgSender(), address(this), _usdtAmount);
      usdtToken.transfer(usdtHolder, _usdtAmount);
      emit Bought(user.userAddress, willSaleTokenAmount, currentRound, block.timestamp);
    } else {
      updateStatistic(user, usdtLeftInRound, tokenLeftInRound);
      usdtToken.transferFrom(_msgSender(), address(this), usdtLeftInRound);
      usdtToken.transfer(usdtHolder, usdtLeftInRound);
      emit Bought(user.userAddress, tokenLeftInRound, currentRound, block.timestamp);
      if (currentRound == totalRound) {
        return;
      }
      currentRound += 1;
      roundStartBlock = block.number;
      emit RoundUpdated(currentRound, roundStartBlock);
      _buy(_usdtAmount.sub(usdtLeftInRound));
    }
  }

  function updateStatistic(User storage user, uint _usdtAmount, uint _gdpAmount) private {
    user.amounts[currentRound] = user.amounts[currentRound].add(_gdpAmount);
    user.totalUSDT = user.totalUSDT.add(_usdtAmount);
    user.totalGDP = user.totalGDP.add(_gdpAmount);
    totalUSDT = totalUSDT.add(_usdtAmount);
    totalGDP = totalGDP.add(_gdpAmount);
    sold[currentRound] = sold[currentRound].add(_gdpAmount);
  }

  function _validateUserCap(User storage user, uint _usdtAmount) private view {
    uint userSpent;
    for (uint i = 1; i <= totalRound; i++) {
      userSpent = userSpent.add(user.amounts[i].div(decimal18).mul(prices[i]));
    }
    require(userSpent.add(_usdtAmount) <= cap, 'GDP PrivateSale: check your cap!!!');
  }
}

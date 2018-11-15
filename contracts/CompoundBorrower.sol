pragma solidity ^0.4.24;

import "./EIP20Interface.sol";
import "./WrappedEtherInterface.sol";
import "./MoneyMarketInterface.sol";

contract CompoundBorrower {
  uint constant expScale = 10**18;
  address tokenAddress;
  address moneyMarketAddress;
  address creator;
  address owner;
  address wethAddress;

  constructor (address _owner, address _tokenAddress, address _wethAddress, address _moneyMarketAddress) public {
    creator = msg.sender;
    owner = _owner;
    tokenAddress = _tokenAddress;
    wethAddress = _wethAddress;
    moneyMarketAddress = _moneyMarketAddress;

    WrappedEtherInterface weth = WrappedEtherInterface(wethAddress);
    weth.approve(moneyMarketAddress, uint(-1));

    EIP20Interface borrowedToken = EIP20Interface(tokenAddress);
    borrowedToken.approve(moneyMarketAddress, uint(-1));
  }

  /* @dev sent from borrow factory, wraps eth and supplies weth, then borrows the token at address supplied in constructor */
  function fund() payable external {
    require(creator == msg.sender);

    WrappedEtherInterface weth = WrappedEtherInterface(wethAddress);
    weth.deposit.value(msg.value)();

    MoneyMarketInterface compoundMoneyMarket = MoneyMarketInterface(moneyMarketAddress);
    compoundMoneyMarket.supply(wethAddress, msg.value);

    borrowAvailableTokens();
  }

  function borrowAvailableTokens() private {
    int excessLiquidity = calculateExcessLiquidity();
    if (excessLiquidity > 0) {
      MoneyMarketInterface compoundMoneyMarket = MoneyMarketInterface(moneyMarketAddress);
      uint assetPrice = compoundMoneyMarket.assetPrices(tokenAddress);
      /* assetPrice contains expScale, so must be factored out */
      /* by including it in numerator */
      uint targetBorrow = uint(excessLiquidity) * expScale / assetPrice;
      compoundMoneyMarket.borrow(tokenAddress, targetBorrow);

      /* this contract will now hold borrowed tokens, sweep them to owner */
      EIP20Interface borrowedToken = EIP20Interface(tokenAddress);
      uint borrowedTokenBalance = borrowedToken.balanceOf(address(this));
      borrowedToken.transfer(owner, borrowedTokenBalance);
    }
  }


  /* @dev the factory contract will transfer tokens necessary to repay */
  function repay() external {
    require(creator == msg.sender);

    MoneyMarketInterface compoundMoneyMarket = MoneyMarketInterface(moneyMarketAddress);
    uint borrowBalance = compoundMoneyMarket.getBorrowBalance(address(this), tokenAddress);
    compoundMoneyMarket.repayBorrow(tokenAddress, uint(-1));

    withdrawExcessSupply();
  }

  function withdrawExcessSupply() private {
    uint amountToWithdraw;
    int excessLiquidity = calculateExcessLiquidity();
    if (excessLiquidity > 0) {
      MoneyMarketInterface compoundMoneyMarket = MoneyMarketInterface(moneyMarketAddress);
      uint borrowBalance = compoundMoneyMarket.getBorrowBalance(address(this), tokenAddress);
      if (borrowBalance == 0) {
        amountToWithdraw = uint(-1);
      } else {
        amountToWithdraw = uint( excessLiquidity );
      }

      compoundMoneyMarket.withdraw(wethAddress, amountToWithdraw);

      WrappedEtherInterface weth = WrappedEtherInterface(wethAddress);
      uint wethBalance = weth.balanceOf(address(this));
      weth.withdraw(wethBalance);
      owner.transfer(address(this).balance);
    }
  }

  function calculateExcessLiquidity() private returns ( int ) {
    MoneyMarketInterface compoundMoneyMarket = MoneyMarketInterface(moneyMarketAddress);
    (uint status, uint totalSupply, uint totalBorrow) = compoundMoneyMarket.calculateAccountValues(address(this));
    /* require(status == 0); */
    int totalPossibleBorrow = int(totalSupply * 4 / 7);
    int liquidity = int( totalPossibleBorrow ) - int( totalBorrow );
    return liquidity;
  }

  // need to accept eth for withdrawing weth
  function () public payable {}
}





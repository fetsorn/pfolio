// SPDX-License-Identifier: MIT
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import "hardhat/console.sol";

library SafeMath {
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "MUL_ERROR");

        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "DIVIDING_ERROR");
        return a / b;
    }

    function divCeil(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 quotient = div(a, b);
        uint256 remainder = a - quotient * b;
        if (remainder > 0) {
            return quotient + 1;
        } else {
            return quotient;
        }
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SUB_ERROR");
        return a - b;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "ADD_ERROR");
        return c;
    }

    function sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = x / 2 + 1;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}

library DecimalMath {
    using SafeMath for uint256;

    uint256 constant ONE = 10**18;

    function mul(uint256 target, uint256 d) internal pure returns (uint256) {
        return target.mul(d) / ONE;
    }

    function mulCeil(uint256 target, uint256 d)
        internal
        pure
        returns (uint256)
    {
        return target.mul(d).divCeil(ONE);
    }

    function divFloor(uint256 target, uint256 d)
        internal
        pure
        returns (uint256)
    {
        return target.mul(ONE).div(d);
    }

    function divCeil(uint256 target, uint256 d)
        internal
        pure
        returns (uint256)
    {
        return target.mul(ONE).divCeil(d);
    }
}

library DODOMath {
    using SafeMath for uint256;

    /*
        Integrate dodo curve fron V1 to V2
        require V0>=V1>=V2>0
        res = (1-k)i(V1-V2)+ikV0*V0(1/V2-1/V1)
        let V1-V2=delta
        res = i*delta*(1-k+k(V0^2/V1/V2))
    */
    function _GeneralIntegrate(
        uint256 V0,
        uint256 V1,
        uint256 V2,
        uint256 i,
        uint256 k
    ) internal pure returns (uint256) {
        uint256 fairAmount = DecimalMath.mul(i, V1.sub(V2)); // i*delta
        uint256 V0V0V1V2 = DecimalMath.divCeil(V0.mul(V0).div(V1), V2);
        uint256 penalty = DecimalMath.mul(k, V0V0V1V2); // k(V0^2/V1/V2)
        return DecimalMath.mul(fairAmount, DecimalMath.ONE.sub(k).add(penalty));
    }

    /*
        The same with integration expression above, we have:
        i*deltaB = (Q2-Q1)*(1-k+kQ0^2/Q1/Q2)
        Given Q1 and deltaB, solve Q2
        This is a quadratic function and the standard version is
        aQ2^2 + bQ2 + c = 0, where
        a=1-k
        -b=(1-k)Q1-kQ0^2/Q1+i*deltaB
        c=-kQ0^2
        and Q2=(-b+sqrt(b^2+4(1-k)kQ0^2))/2(1-k)
        note: another root is negative, abondan
        if deltaBSig=true, then Q2>Q1
        if deltaBSig=false, then Q2<Q1
    */
    function _SolveQuadraticFunctionForTrade(
        uint256 Q0,
        uint256 Q1,
        uint256 ideltaB,
        bool deltaBSig,
        uint256 k
    ) internal pure returns (uint256) {
        // calculate -b value and sig
        // -b = (1-k)Q1-kQ0^2/Q1+i*deltaB
        uint256 kQ02Q1 = DecimalMath.mul(k, Q0).mul(Q0).div(Q1); // kQ0^2/Q1
        uint256 b = DecimalMath.mul(DecimalMath.ONE.sub(k), Q1); // (1-k)Q1
        bool minusbSig = true;
        if (deltaBSig) {
            b = b.add(ideltaB); // (1-k)Q1+i*deltaB
        } else {
            kQ02Q1 = kQ02Q1.add(ideltaB); // i*deltaB+kQ0^2/Q1
        }
        if (b >= kQ02Q1) {
            b = b.sub(kQ02Q1);
            minusbSig = true;
        } else {
            b = kQ02Q1.sub(b);
            minusbSig = false;
        }

        // calculate sqrt
        uint256 squareRoot =
            DecimalMath.mul(
                DecimalMath.ONE.sub(k).mul(4),
                DecimalMath.mul(k, Q0).mul(Q0)
            ); // 4(1-k)kQ0^2
        squareRoot = b.mul(b).add(squareRoot).sqrt(); // sqrt(b*b+4(1-k)kQ0*Q0)

        // final res
        uint256 denominator = DecimalMath.ONE.sub(k).mul(2); // 2(1-k)
        uint256 numerator;
        if (minusbSig) {
            numerator = b.add(squareRoot);
        } else {
            numerator = squareRoot.sub(b);
        }

        if (deltaBSig) {
            return DecimalMath.divFloor(numerator, denominator);
        } else {
            return DecimalMath.divCeil(numerator, denominator);
        }
    }

    /*
        Start from the integration function
        i*deltaB = (Q2-Q1)*(1-k+kQ0^2/Q1/Q2)
        Assume Q2=Q0, Given Q1 and deltaB, solve Q0
        let fairAmount = i*deltaB
    */
    function _SolveQuadraticFunctionForTarget(
        uint256 V1,
        uint256 k,
        uint256 fairAmount
    ) internal pure returns (uint256 V0) {
        // V0 = V1+V1*(sqrt-1)/2k
        uint256 sqrt =
            DecimalMath.divCeil(DecimalMath.mul(k, fairAmount).mul(4), V1);
        sqrt = sqrt.add(DecimalMath.ONE).mul(DecimalMath.ONE).sqrt();
        uint256 premium =
            DecimalMath.divCeil(sqrt.sub(DecimalMath.ONE), k.mul(2));
        // V0 is greater than or equal to V1 according to the solution
        return DecimalMath.mul(V1, DecimalMath.ONE.add(premium));
    }
}

library Types {
    enum RStatus {ONE, ABOVE_ONE, BELOW_ONE}
}

library SafeERC20 {
    using SafeMath for uint256;

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transfer.selector, to, value)
        );
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transferFrom.selector, from, to, value)
        );
    }

    function safeApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.approve.selector, spender, value)
        );
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves.

        // A Solidity high level call has three parts:
        // 1. The target address is checked to verify it contains contract code
        // 2. The call itself is made, and success asserted
        // 3. The return value is decoded, which in turn checks the size of the returned data.
        // solhint-disable-next-line max-line-length

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeERC20: low-level call failed");

        if (returndata.length > 0) {
            // Return data is optional
            // solhint-disable-next-line max-line-length
            require(
                abi.decode(returndata, (bool)),
                "SafeERC20: ERC20 operation did not succeed"
            );
        }
    }
}

interface IDODOLpToken {
    function mint(address user, uint256 value) external;

    function burn(address user, uint256 value) external;

    function balanceOf(address owner) external view returns (uint256);

    function totalSupply() external view returns (uint256);
}

interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    function decimals() external view returns (uint8);

    function name() external view returns (string memory);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
}

interface IDODOCallee {
    function dodoCall(
        bool isBuyBaseToken,
        uint256 baseAmount,
        uint256 quoteAmount,
        bytes calldata data
    ) external;
}

interface IOracle {
    function getPrice() external view returns (uint256);
}

contract BConst {
    uint256 public constant BONE = 10**18;

    uint256 public constant MIN_BOUND_TOKENS = 2;
    uint256 public constant MAX_BOUND_TOKENS = 8;

    uint256 public constant MIN_FEE = BONE / 10**6;
    uint256 public constant MAX_FEE = BONE / 10;
    uint256 public constant EXIT_FEE = 0;

    uint256 public constant MIN_BALANCE = BONE / 10**12;

    uint256 public constant INIT_POOL_SUPPLY = BONE * 100;

    uint256 public constant MIN_BPOW_BASE = 1 wei;
    uint256 public constant MAX_BPOW_BASE = (2 * BONE) - 1 wei;
    uint256 public constant BPOW_PRECISION = BONE / 10**10;

    uint256 public constant MAX_IN_RATIO = BONE / 2;
    uint256 public constant MAX_OUT_RATIO = (BONE / 3) + 1 wei;

    uint256 MAX_INT =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
}

contract BNum is BConst {
    function btoi(uint256 a) internal pure returns (uint256) {
        return a / BONE;
    }

    function bfloor(uint256 a) internal pure returns (uint256) {
        return btoi(a) * BONE;
    }

    function badd(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "ERR_ADD_OVERFLOW");
        return c;
    }

    function bsub(uint256 a, uint256 b) internal pure returns (uint256) {
        (uint256 c, bool flag) = bsubSign(a, b);
        require(!flag, "ERR_SUB_UNDERFLOW");
        return c;
    }

    function bsubSign(uint256 a, uint256 b)
        internal
        pure
        returns (uint256, bool)
    {
        if (a >= b) {
            return (a - b, false);
        } else {
            return (b - a, true);
        }
    }

    function bmul(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c0 = a * b;
        require(a == 0 || c0 / a == b, "ERR_MUL_OVERFLOW");
        uint256 c1 = c0 + (BONE / 2);
        require(c1 >= c0, "ERR_MUL_OVERFLOW");
        uint256 c2 = c1 / BONE;
        return c2;
    }

    function bdiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "ERR_DIV_ZERO");
        uint256 c0 = a * BONE;
        require(a == 0 || c0 / a == BONE, "ERR_DIV_INTERNAL"); // bmul overflow
        uint256 c1 = c0 + (b / 2);
        require(c1 >= c0, "ERR_DIV_INTERNAL"); // badd require
        uint256 c2 = c1 / b;
        return c2;
    }

    // DSMath.wpow
    function bpowi(uint256 a, uint256 n) internal pure returns (uint256) {
        uint256 z = n % 2 != 0 ? a : BONE;

        for (n /= 2; n != 0; n /= 2) {
            a = bmul(a, a);

            if (n % 2 != 0) {
                z = bmul(z, a);
            }
        }
        return z;
    }

    // Compute b^(e.w) by splitting it into (b^e)*(b^0.w).
    // Use `bpowi` for `b^e` and `bpowK` for k iterations
    // of approximation of b^0.w
    function bpow(uint256 base, uint256 exp) internal pure returns (uint256) {
        require(base >= MIN_BPOW_BASE, "ERR_BPOW_BASE_TOO_LOW");
        require(base <= MAX_BPOW_BASE, "ERR_BPOW_BASE_TOO_HIGH");

        uint256 whole = bfloor(exp);
        uint256 remain = bsub(exp, whole);

        uint256 wholePow = bpowi(base, btoi(whole));

        if (remain == 0) {
            return wholePow;
        }

        uint256 partialResult = bpowApprox(base, remain, BPOW_PRECISION);
        return bmul(wholePow, partialResult);
    }

    function bpowApprox(
        uint256 base,
        uint256 exp,
        uint256 precision
    ) internal pure returns (uint256) {
        // term 0:
        uint256 a = exp;
        (uint256 x, bool xneg) = bsubSign(base, BONE);
        uint256 term = BONE;
        uint256 sum = term;
        bool negative = false;

        // term(k) = numer / denom
        // = (product(a - i - 1, i=1-->k) * x^k) / (k!)
        // each iteration, multiply previous term by (a-(k-1)) * x / k
        // continue until term is less than precision
        for (uint256 i = 1; term >= precision; i++) {
            uint256 bigK = i * BONE;
            (uint256 c, bool cneg) = bsubSign(a, bsub(bigK, BONE));
            term = bmul(term, bmul(c, x));
            term = bdiv(term, bigK);
            if (term == 0) break;

            if (xneg) negative = !negative;
            if (cneg) negative = !negative;
            if (negative) {
                sum = bsub(sum, term);
            } else {
                sum = badd(sum, term);
            }
        }

        return sum;
    }
}

contract BTokenBase is BNum {
    mapping(address => uint256) internal _balance;
    mapping(address => mapping(address => uint256)) internal _allowance;
    uint256 internal _totalSupply;

    event Approval(address indexed src, address indexed dst, uint256 amt);
    event Transfer(address indexed src, address indexed dst, uint256 amt);

    function _mint(uint256 amt) internal {
        _balance[address(this)] = badd(_balance[address(this)], amt);
        _totalSupply = badd(_totalSupply, amt);
        emit Transfer(address(0), address(this), amt);
    }

    function _burn(uint256 amt) internal {
        require(_balance[address(this)] >= amt, "ERR_INSUFFICIENT_BAL");
        _balance[address(this)] = bsub(_balance[address(this)], amt);
        _totalSupply = bsub(_totalSupply, amt);
        emit Transfer(address(this), address(0), amt);
    }

    function _move(
        address src,
        address dst,
        uint256 amt
    ) internal {
        require(_balance[src] >= amt, "ERR_INSUFFICIENT_BAL");
        _balance[src] = bsub(_balance[src], amt);
        _balance[dst] = badd(_balance[dst], amt);
        emit Transfer(src, dst, amt);
    }

    function _push(address to, uint256 amt) internal {
        _move(address(this), to, amt);
    }

    function _pull(address from, uint256 amt) internal {
        _move(from, address(this), amt);
    }
}

contract BToken is BTokenBase, IERC20 {
    string private _name = "Balancer Pool Token";
    string private _symbol = "BPT";
    uint8 private _decimals = 18;

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function allowance(address src, address dst)
        external
        view
        override
        returns (uint256)
    {
        return _allowance[src][dst];
    }

    function balanceOf(address whom) external view override returns (uint256) {
        return _balance[whom];
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function approve(address dst, uint256 amt)
        external
        override
        returns (bool)
    {
        _allowance[msg.sender][dst] = amt;
        emit Approval(msg.sender, dst, amt);
        return true;
    }

    function increaseApproval(address dst, uint256 amt)
        external
        returns (bool)
    {
        _allowance[msg.sender][dst] = badd(_allowance[msg.sender][dst], amt);
        emit Approval(msg.sender, dst, _allowance[msg.sender][dst]);
        return true;
    }

    function decreaseApproval(address dst, uint256 amt)
        external
        returns (bool)
    {
        uint256 oldValue = _allowance[msg.sender][dst];
        if (amt > oldValue) {
            _allowance[msg.sender][dst] = 0;
        } else {
            _allowance[msg.sender][dst] = bsub(oldValue, amt);
        }
        emit Approval(msg.sender, dst, _allowance[msg.sender][dst]);
        return true;
    }

    function transfer(address dst, uint256 amt)
        external
        override
        returns (bool)
    {
        _move(msg.sender, dst, amt);
        return true;
    }

    function transferFrom(
        address src,
        address dst,
        uint256 amt
    ) external override returns (bool) {
        require(
            msg.sender == src || amt <= _allowance[src][msg.sender],
            "ERR_BTOKEN_BAD_CALLER"
        );
        _move(src, dst, amt);
        if (msg.sender != src && _allowance[src][msg.sender] != uint256(-1)) {
            _allowance[src][msg.sender] = bsub(
                _allowance[src][msg.sender],
                amt
            );
            emit Approval(msg.sender, dst, _allowance[src][msg.sender]);
        }
        return true;
    }
}

contract LPToken is BToken {
    // ==
    // 'Underlying' token-manipulation functions make external calls but are NOT locked
    // You must `_lock_` or otherwise ensure reentry-safety

    function _pullUnderlying(
        address erc20,
        address from,
        uint256 amount
    ) internal {
        bool xfer = IERC20(erc20).transferFrom(from, address(this), amount);
        require(xfer, "ERR_ERC20_FALSE");
    }

    function _pushUnderlying(
        address erc20,
        address to,
        uint256 amount
    ) internal {
        bool xfer = IERC20(erc20).transfer(to, amount);
        require(xfer, "ERR_ERC20_FALSE");
    }

    function _pullPoolShare(address from, uint256 amount) internal {
        _pull(from, amount);
    }

    function _pushPoolShare(address to, uint256 amount) internal {
        _push(to, amount);
    }

    function _mintPoolShare(uint256 amount) internal {
        _mint(amount);
    }

    function _burnPoolShare(uint256 amount) internal {
        _burn(amount);
    }
}

contract Storage {
    using SafeMath for uint256;

    struct Record {
        bool bound; // is token bound to pool
        uint256 index; // private
        uint256 balance;
        Types.RStatus RStatus;
        uint256 target;
        uint256 balanceLimit;
        address token;
        uint256 price;
        uint256 min;
        uint256 max;
    }

    address public _factory; // BFactory address to push token exitFee to
    address public _controller; // has CONTROL role
    bool public _publicSwap; // true if PUBLIC can call SWAP functions

    // `setSwapFee` and `finalize` require CONTROL
    // `finalize` sets `PUBLIC can SWAP`, `PUBLIC can JOIN`
    uint256 public _swapFee;
    bool public _finalized;

    address[] public _tokens;

    bool public DEBUG_PRICE = true;
    bool public DEBUG_TRADE = true;

    mapping(address => Record) public _records;

    uint256 public _portfolioValue;

    event LOG_CALL(
        bytes4 indexed sig,
        address indexed caller,
        bytes data
    ) anonymous;

    modifier _logs_() {
        emit LOG_CALL(msg.sig, msg.sender, msg.data);
        _;
    }

    modifier _lock_() {
        require(!_mutex, "ERR_REENTRY");
        _mutex = true;
        _;
        _mutex = false;
    }

    modifier _viewlock_() {
        require(!_mutex, "ERR_REENTRY");
        _;
    }

    bool private _mutex;

    function isPublicSwap() external view returns (bool) {
        return _publicSwap;
    }

    function isFinalized() external view returns (bool) {
        return _finalized;
    }

    function isBound(address t) external view returns (bool) {
        return _records[t].bound;
    }

    function getNumTokens() external view returns (uint256) {
        return _tokens.length;
    }

    function getCurrentTokens()
        external
        view
        _viewlock_
        returns (address[] memory tokens)
    {
        return _tokens;
    }

    function getFinalTokens()
        external
        view
        _viewlock_
        returns (address[] memory tokens)
    {
        require(_finalized, "ERR_NOT_FINALIZED");
        return _tokens;
    }

    function getBalance(address token)
        external
        view
        _viewlock_
        returns (uint256)
    {
        require(_records[token].bound, "ERR_NOT_BOUND");
        return _records[token].balance;
    }

    function getTarget(address token)
        external
        view
        _viewlock_
        returns (uint256)
    {
        require(_records[token].bound, "ERR_NOT_BOUND");
        return _records[token].target;
    }

    function getR(address token)
        public
        view
        _viewlock_
        returns (string memory)
    {
        require(_records[token].bound, "ERR_NOT_BOUND");

        Types.RStatus r = _records[token].RStatus;

        return mapR(r);
    }

    function mapR(Types.RStatus r)
        internal
        view
        _viewlock_
        returns (string memory)
    {
        if (r == Types.RStatus.ONE) {
            return "ONE";
        } else if (r == Types.RStatus.ABOVE_ONE) {
            return "ABOVE_ONE";
        } else {
            return "BELOW_ONE";
        }
    }

    function getMin(address token)
        external
        view
        _viewlock_
        returns (uint256 min)
    {
        require(_records[token].bound, "ERR_NOT_BOUND");
        return _records[token].min;
    }

    function getMax(address token)
        external
        view
        _viewlock_
        returns (uint256 max)
    {
        require(_records[token].bound, "ERR_NOT_BOUND");
        return _records[token].max;
    }

    function getSwapFee() external view _viewlock_ returns (uint256) {
        return _swapFee;
    }

    function getController() external view _viewlock_ returns (address) {
        return _controller;
    }

    //TODO: will take prices from oracles
    function setOraclePrice(address token, uint256 price) external {
        // TODO: fails ungracefully on unbound tokens
        // TODO: mock function, will take pricefeeds from oracles
        _records[token].price = price;
    }

    // price in usd in decimal 10**18
    // assumes token price is up-to-date
    function getAssetPrice(address token) public view returns (uint256) {
        // TODO: fails ungracefully on unbound tokens
        // TODO: mock function, will take pricefeeds from oracles
        // TODO: assumes all pricefeeds have the same precision, will have to convert in prod
        return _records[token].price;
    }

    // price base relative to quote in decimal 10**18
    // assumes asset prices are up-to-date
    function getTransactionPrice(address base, address quote)
        public
        view
        returns (uint256)
    {
        // TODO: fails ungracefully on unbound tokens
        // TODO: mock function, will take pricefeeds from oracles
        // TODO: choose the sort of division - floor, ceiling
        return
            DecimalMath.divFloor(_records[base].price, _records[quote].price);
    }

    // assumes asset prices are up-to-date
    function updatePortfolioValue() public {
        uint256 i;
        address token;
        uint256 value;
        _portfolioValue = 0;

        // console.log("_tokens length is %s", _tokens.length); // ORACLE_DEBUG

        for (i = 0; i < _tokens.length; i++) {
            token = _tokens[i];
            value = _records[token].balance.mul(_records[token].price); // balance * price

            // console.log("token %s value is %s", i+1, value); // ORACLE_DEBUG

            _portfolioValue = _portfolioValue.add(value);
        }
    }

    // assumes asset prices and _portfolioValue are up-to-date
    function getCurrentShare(address asset) public view returns (uint256) {
        uint256 assetValue = _records[asset].balance.mul(_records[asset].price);

        // console.log("token value is %s", value); // ORACLE_DEBUG

        return DecimalMath.divFloor(assetValue, _portfolioValue);
    }

    // assumes asset prices and _portfolioValue are up-to-date
    function checkSharesAfterTx(
        address gain,
        address loss,
        uint256 gainReserveAfterTx,
        uint256 lossReserveAfterTx
    ) public view {
        // take price of token1 in usd
        // take price of all tokens in usd - in state?
        /// add all shares of tokens from reserves
        // decimal divide

        uint256 gainValueBeforeTx =
            _records[gain].balance.mul(_records[gain].price);
        uint256 lossValueBeforeTx =
            _records[loss].balance.mul(_records[loss].price);

        uint256 gainValueAfterTx = gainReserveAfterTx.mul(_records[gain].price);
        uint256 lossValueAfterTx =
            lossReserveAfterTx.mul(_records[loss].price);

        // console.log("token value is %s", value); // ORACLE_DEBUG
        uint256 portfolioValueAfterTx;
        portfolioValueAfterTx = _portfolioValue.add(gainValueAfterTx).add(
            lossValueAfterTx
        );
        portfolioValueAfterTx = portfolioValueAfterTx.sub(gainValueBeforeTx).sub(
            lossValueBeforeTx
        );

        // console.log("whole value is %s", wholeValueAfterTx); // ORACLE_DEBUG

        uint256 gainShareAfterTx =
            DecimalMath.divFloor(gainValueAfterTx, portfolioValueAfterTx);
        uint256 lossShareAfterTx =
            DecimalMath.divFloor(lossValueAfterTx, portfolioValueAfterTx);

        // share of base and quote after tx should be within share limits
        require(
            gainShareAfterTx <= _records[gain].max,
            "GAIN OUTSIDE MAX"
        );
        require(
            _records[loss].min <= lossShareAfterTx,
            "LOSS OUTSIDE MIN"
        );
    }

    function setK(uint256 k) external returns (uint256) {
        _K_ = k;
        return k;
    }

    // ReentrancyGuard

    // https://solidity.readthedocs.io/en/latest/control-structures.html?highlight=zero-state#scoping-and-declarations
    // zero-state of _ENTERED_ is false
    bool private _ENTERED_;

    modifier preventReentrant() {
        require(!_ENTERED_, "REENTRANT");
        _ENTERED_ = true;
        _;
        _ENTERED_ = false;
    }

    // ============ Core Address ============

    address public _SUPERVISOR_; // could freeze system in emergency
    address public _MAINTAINER_; // collect maintainer fee to buy food for DODO

    // ============ Variables for PMM Algorithm ============

    uint256 public _K_;

    // ============ Version Control ============
    function version() external pure returns (uint256) {
        return 101; // 0.0.1
    }
}

contract Admin is Storage, LPToken {
    using SafeMath for uint256;

    function setSwapFee(uint256 swapFee) external _logs_ _lock_ {
        require(!_finalized, "ERR_IS_FINALIZED");
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        require(swapFee >= MIN_FEE, "ERR_MIN_FEE");
        require(swapFee <= MAX_FEE, "ERR_MAX_FEE");
        _swapFee = swapFee;
    }

    function setController(address manager) external _logs_ _lock_ {
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        _controller = manager;
    }

    function setPublicSwap(bool public_) external _logs_ _lock_ {
        require(!_finalized, "ERR_IS_FINALIZED");
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        _publicSwap = public_;
    }

    function finalize() external _logs_ _lock_ {
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        require(!_finalized, "ERR_IS_FINALIZED");
        require(_tokens.length >= MIN_BOUND_TOKENS, "ERR_MIN_TOKENS");

        _finalized = true;
        _publicSwap = true;

        _mintPoolShare(INIT_POOL_SUPPLY);
        _pushPoolShare(msg.sender, INIT_POOL_SUPPLY);
    }

    function bind(
        address token,
        uint256 balance,
        uint256 min,
        uint256 max
    )
        external
        _logs_
    // _lock_  Bind does not lock because it jumps to `rebind`, which does
    {
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        require(!_records[token].bound, "ERR_IS_BOUND");
        require(!_finalized, "ERR_IS_FINALIZED");

        require(_tokens.length < MAX_BOUND_TOKENS, "ERR_MAX_TOKENS");

        _records[token] = Record({
            bound: true,
            index: _tokens.length,
            balance: 0, // and set by `rebind`
            RStatus: Types.RStatus.ONE,
            target: 0,
            balanceLimit: MAX_INT,
            token: token,
            price: 0, // set by `rebind`
            min: 0, // set by `rebind`
            max: 0 // set by `rebind`
        });
        _tokens.push(token);
        rebind(token, balance);
        adjustShareLimits(token, min, max);
    }

    function rebind(address token, uint256 balance) public _logs_ _lock_ {
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        require(_records[token].bound, "ERR_NOT_BOUND");
        require(!_finalized, "ERR_IS_FINALIZED");

        require(balance >= MIN_BALANCE, "ERR_MIN_BALANCE");

        // Adjust the balance record and actual token balance
        uint256 oldBalance = _records[token].balance;
        _records[token].balance = balance;
        _records[token].target = balance;
        if (balance > oldBalance) {
            _pullUnderlying(token, msg.sender, bsub(balance, oldBalance));
        } else if (balance < oldBalance) {
            // In this case liquidity is being withdrawn, so charge EXIT_FEE
            uint256 tokenBalanceWithdrawn = bsub(oldBalance, balance);
            uint256 tokenExitFee = bmul(tokenBalanceWithdrawn, EXIT_FEE);
            _pushUnderlying(
                token,
                msg.sender,
                bsub(tokenBalanceWithdrawn, tokenExitFee)
            );
            _pushUnderlying(token, _factory, tokenExitFee);
        }
    }

    function adjustShareLimits(
        address token,
        uint256 min,
        uint256 max
    ) public {
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        require(_records[token].bound, "ERR_NOT_BOUND");

        // Adjust the min and max share limits
        _records[token].min = min;
        _records[token].max = max;

        // TODO: check if old balance is outside new limits
    }

    function unbind(address token) external _logs_ _lock_ {
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        require(_records[token].bound, "ERR_NOT_BOUND");
        require(!_finalized, "ERR_IS_FINALIZED");

        uint256 tokenBalance = _records[token].balance;
        uint256 tokenExitFee = bmul(tokenBalance, EXIT_FEE);

        // Swap the token-to-unbind with the last token,
        // then delete the last token
        uint256 index = _records[token].index;
        uint256 last = _tokens.length - 1;
        _tokens[index] = _tokens[last];
        _records[_tokens[index]].index = index;
        _tokens.pop();
        _records[token] = Record({
            bound: false,
            index: 0,
            balance: 0,
            RStatus: Types.RStatus.ONE,
            target: 0,
            balanceLimit: MAX_INT,
            token: token,
            price: 0,
            min: 0,
            max: 0
        });

        _pushUnderlying(token, msg.sender, bsub(tokenBalance, tokenExitFee));
        _pushUnderlying(token, _factory, tokenExitFee);
    }

    // InitializableOwnable

    address public _OWNER_;
    address public _NEW_OWNER_;

    // ============ Events ============

    event OwnershipTransferPrepared(
        address indexed previousOwner,
        address indexed newOwner
    );

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    // ============ Modifiers ============

    modifier onlyOwner() {
        require(msg.sender == _OWNER_, "NOT_OWNER");
        _;
    }

    // ============ Functions ============

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "INVALID_OWNER");
        emit OwnershipTransferPrepared(_OWNER_, newOwner);
        _NEW_OWNER_ = newOwner;
    }

    function claimOwnership() external {
        require(msg.sender == _NEW_OWNER_, "INVALID_CLAIM");
        emit OwnershipTransferred(_OWNER_, _NEW_OWNER_);
        _OWNER_ = _NEW_OWNER_;
        _NEW_OWNER_ = address(0);
    }
}

contract TestMath {
    using SafeMath for uint256;

    // ============ Math functions ============

    /*
        Integrate dodo curve fron V1 to V2
        require V0>=V1>=V2>0
        res = (1-k)i(V1-V2)+ikV0*V0(1/V2-1/V1)
        let V1-V2=delta
        res = i*delta*(1-k+k(V0^2/V1/V2))
    */
    function GeneralIntegrate(
        uint256 V0,
        uint256 V1,
        uint256 V2,
        uint256 i,
        uint256 k
    ) public view returns (uint256) {
        // console.log("GeneralIntegrate  (V0:%s, V1:%s, V2:%s, i, k)", V0, V1, V2); //PRICE_DEBUG
        // console.log("GeneralIntegrate  (V0, V1, V2, i:%s, k:%s)", i, k); //PRICE_DEBUG
        uint256 fairAmount = DecimalMath.mul(i, V1.sub(V2)); // i*delta
        // console.log("GeneralIntegrate:  fairAmount is i:%s * (B2:%s - B1:%s)", i, V1, V2); //PRICE_DEBUG
        // console.log("GeneralIntegrate:  fairAmount is %s * %s, is %s", i, V1.sub(V2), fairAmount); //PRICE_DEBUG
        uint256 V0V0V1V2 = DecimalMath.divCeil(V0.mul(V0).div(V1), V2);
        uint256 penalty = DecimalMath.mul(k, V0V0V1V2); // k(V0^2/V1/V2)
        // console.log("GeneralIntegrate:  penalty is k   * (B0:%s^2/V1:%s/V2:%s)", V0, V1, V2); //PRICE_DEBUG
        // console.log("GeneralIntegrate:  penalty is k   * (%s/%s/%s)", V0.mul(V0), V1, V2); //PRICE_DEBUG
        // console.log("GeneralIntegrate:  penalty is k   * (%s/%s)", V0.mul(V0).div(V1), V2); //PRICE_DEBUG
        // console.log("GeneralIntegrate:  penalty is k   * (%s)", V0V0V1V2); //PRICE_DEBUG
        // console.log("GeneralIntegrate:  penalty is %s", penalty); //PRICE_DEBUG

        // console.log("GeneralIntegrate:  deltaQ  is fairAmount:%s * (1-k:%s + penalty:%s)", fairAmount, DecimalMath.ONE.sub(k), penalty); //PRICE_DEBUG
        // console.log("GeneralIntegrate:  deltaQ  is %s * %s", fairAmount, DecimalMath.ONE.sub(k).add(penalty)); //PRICE_DEBUG
        // console.log("GeneralIntegrate:  deltaQ  is %s", DecimalMath.mul(fairAmount, DecimalMath.ONE.sub(k).add(penalty))); //PRICE_DEBUG
        return DecimalMath.mul(fairAmount, DecimalMath.ONE.sub(k).add(penalty));
    }

    /*
        The same with integration expression above, we have:
        i*deltaB = (Q2-Q1)*(1-k+kQ0^2/Q1/Q2)
        Given Q1 and deltaB, solve Q2
        This is a quadratic function and the standard version is
        aQ2^2 + bQ2 + c = 0, where
        a=1-k
        -b=(1-k)Q1-kQ0^2/Q1+i*deltaB
        c=-kQ0^2
        and Q2=(-b+sqrt(b^2+4(1-k)kQ0^2))/2(1-k)
        note: another root is negative, abondan
        if deltaBSig=true, then Q2>Q1
        if deltaBSig=false, then Q2<Q1
    */
    function SolveQuadraticFunctionForTrade(
        uint256 Q0,
        uint256 Q1,
        uint256 ideltaB,
        bool deltaBSig,
        uint256 k
    ) public view returns (uint256) {
        // console.log("SolveQuadraticFunctionForTrade (Q0:%s, Q1:%s, ideltaB:%s, deltaBSig, k)", Q0, Q1, ideltaB); //PRICE_DEBUG
        // console.log("SolveQuadraticFunctionForTrade (Q0, Q1, ideltaB, deltaBSig:%s, k:%s)", deltaBSig, k); //PRICE_DEBUG

        // console.log("SolveQuadraticFunctionForTrade: Q2 is (-b + sqrt(b^2+4ac))/2a"); //PRICE_DEBUG

        // console.log("SolveQuadraticFunctionForTrade:  b is (kQ0^2/Q1)-Q1+(kQ1)-(i*deltaB)"); //PRICE_DEBUG
        // console.log("SolveQuadraticFunctionForTrade: -b is (1-k)Q1-(kQ0^2/Q1)+(i*deltaB)"); //PRICE_DEBUG
        // calculate -b value and sig
        // -b = (1-k)Q1-kQ0^2/Q1+i*deltaB
        uint256 kQ02Q1 = DecimalMath.mul(k, Q0).mul(Q0).div(Q1); // kQ0^2/Q1

        // console.log("SolveQuadraticFunctionForTrade: kQ0Q0/Q1 is k*%s*%s/%s", Q0, Q0, Q1); //PRICE_DEBUG
        // console.log("SolveQuadraticFunctionForTrade: kQ0Q0/Q1 is %s*%s/%s", DecimalMath.mul(k, Q0), Q0, Q1); //PRICE_DEBUG
        // console.log("SolveQuadraticFunctionForTrade: kQ0Q0/Q1 is %s/%s", DecimalMath.mul(k, Q0).mul(Q0), Q1); //PRICE_DEBUG
        // console.log("SolveQuadraticFunctionForTrade: kQ0Q0/Q1 is %s", kQ02Q1); //PRICE_DEBUG

        uint256 b = DecimalMath.mul(DecimalMath.ONE.sub(k), Q1); // (1-k)Q1

        // console.log("SolveQuadraticFunctionForTrade: (1-k)Q1 is 0.9*%s", Q1); //PRICE_DEBUG
        // console.log("SolveQuadraticFunctionForTrade: (1-k)Q1 is %s", b); //PRICE_DEBUG

        bool minusbSig = true;
        if (deltaBSig) {
            // console.log("SolveQuadraticFunctionForTrade: (1-k)Q1+(i*deltaB) is %s+%s", b, ideltaB); //PRICE_DEBUG
            b = b.add(ideltaB); // (1-k)Q1+i*deltaB
            // console.log("SolveQuadraticFunctionForTrade: (1-k)Q1+(i*deltaB) is %s", b); //PRICE_DEBUG
        } else {
            // console.log("SolveQuadraticFunctionForTrade: (kQ0^2/Q1)+(i*deltaB) is %s+%s", kQ02Q1, ideltaB); //PRICE_DEBUG
            kQ02Q1 = kQ02Q1.add(ideltaB); // i*deltaB+kQ0^2/Q1
            // console.log("SolveQuadraticFunctionForTrade: (kQ0^2/Q1)+(i*deltaB) is %s", kQ02Q1); //PRICE_DEBUG
        }

        // console.log("SolveQuadraticFunctionForTrade: -b is (1-k)Q1-(kQ0^2/Q1)+(i*deltaB)"); //PRICE_DEBUG
        // console.log("SolveQuadraticFunctionForTrade: -b is %s-%s", b, kQ02Q1); //PRICE_DEBUG
        if (b >= kQ02Q1) {
            b = b.sub(kQ02Q1);
            minusbSig = true;
            // console.log("SolveQuadraticFunctionForTrade: -b is %s", b); //PRICE_DEBUG
        } else {
            b = kQ02Q1.sub(b);
            minusbSig = false;
            // console.log("SolveQuadraticFunctionForTrade: -b is -%s", b); //PRICE_DEBUG
        }

        // calculate sqrt
        uint256 squareRoot =
            DecimalMath.mul(
                DecimalMath.ONE.sub(k).mul(4),
                DecimalMath.mul(k, Q0).mul(Q0)
            ); // 4(1-k)kQ0^2

        // console.log("SolveQuadraticFunctionForTrade: Q2 is (-b + sqrt(b^2+4ac))/2a"); //PRICE_DEBUG
        // console.log("SolveQuadraticFunctionForTrade: 4a is 4(1-k), is %s", DecimalMath.ONE.sub(k).mul(4)); //PRICE_DEBUG
        // console.log("SolveQuadraticFunctionForTrade: c is k*Q0^2, is 0.1*%s^2, is %s", Q0, DecimalMath.mul(k, Q0).mul(Q0)); //PRICE_DEBUG
        // uint256 a4 = DecimalMath.ONE.sub(k).mul(4);  //PRICE_DEBUG
        // uint256 c = DecimalMath.mul(k, Q0).mul(Q0);  //PRICE_DEBUG
        // console.log("SolveQuadraticFunctionForTrade: 4ac is 4a:%s * c:%s, is %s", a4, c, squareRoot); //PRICE_DEBUG
        // console.log("SolveQuadraticFunctionForTrade: Q2 is (-b + sqrt(b^2+4ac))/2a"); //PRICE_DEBUG
        // console.log("SolveQuadraticFunctionForTrade: Q2 is (-b + sqrt(b^2 + %s))/2a", squareRoot); //PRICE_DEBUG
        // console.log("SolveQuadraticFunctionForTrade: Q2 is (-b + sqrt(%s^2 + %s))/2a", b, squareRoot); //PRICE_DEBUG
        // console.log("SolveQuadraticFunctionForTrade: Q2 is (-b + sqrt(%s + %s))/2a", b.mul(b), squareRoot); //PRICE_DEBUG
        // console.log("SolveQuadraticFunctionForTrade: Q2 is (-b + sqrt(%s))/2a", b.mul(b).add(squareRoot)); //PRICE_DEBUG
        squareRoot = b.mul(b).add(squareRoot).sqrt(); // sqrt(b*b+4(1-k)kQ0*Q0)

        // console.log("SolveQuadraticFunctionForTrade: Q2 is (-b + %s)/2a", squareRoot); //PRICE_DEBUG

        // final res
        uint256 denominator = DecimalMath.ONE.sub(k).mul(2); // 2(1-k)

        // console.log("SolveQuadraticFunctionForTrade: 2a is 2(1-k)"); //PRICE_DEBUG
        // console.log("SolveQuadraticFunctionForTrade: 2a is 2(%s - %s)",DecimalMath.ONE, k); //PRICE_DEBUG
        // console.log("SolveQuadraticFunctionForTrade: 2a is 2(%s)", DecimalMath.ONE.sub(k)); //PRICE_DEBUG
        // console.log("SolveQuadraticFunctionForTrade: 2a is %s", denominator); //PRICE_DEBUG

        uint256 numerator;
        if (minusbSig) {
            numerator = b.add(squareRoot);

            // console.log("SolveQuadraticFunctionForTrade: Q2 is (%s + %s)/%s", squareRoot, b, denominator); //PRICE_DEBUG
            // console.log("SolveQuadraticFunctionForTrade: Q2 is %s/%s", numerator, denominator); //PRICE_DEBUG
        } else {
            numerator = squareRoot.sub(b);

            // console.log("SolveQuadraticFunctionForTrade: Q2 is (%s - %s)/%s", squareRoot, b, denominator); //PRICE_DEBUG
            // console.log("SolveQuadraticFunctionForTrade: Q2 is %s/%s", numerator, denominator); //PRICE_DEBUG
        }

        if (deltaBSig) {
            // console.log("SolveQuadraticFunctionForTrade: Q2 is %s", DecimalMath.divFloor(numerator, denominator)); //PRICE_DEBUG
            return DecimalMath.divFloor(numerator, denominator);
        } else {
            // console.log("SolveQuadraticFunctionForTrade: Q2 is %s", DecimalMath.divCeil(numerator, denominator)); //PRICE_DEBUG
            return DecimalMath.divCeil(numerator, denominator);
        }
    }

    /*
        Start from the integration function
        i*deltaB = (Q2-Q1)*(1-k+kQ0^2/Q1/Q2)
        Assume Q2=Q0, Given Q1 and deltaB, solve Q0
        let fairAmount = i*deltaB
    */
    function SolveQuadraticFunctionForTarget(
        uint256 V1,
        uint256 k,
        uint256 fairAmount
    ) public pure returns (uint256 V0) {
        // V0 = V1+V1*(sqrt-1)/2k
        uint256 sqrt =
            DecimalMath.divCeil(DecimalMath.mul(k, fairAmount).mul(4), V1);
        sqrt = sqrt.add(DecimalMath.ONE).mul(DecimalMath.ONE).sqrt();
        uint256 premium =
            DecimalMath.divCeil(sqrt.sub(DecimalMath.ONE), k.mul(2));
        // V0 is greater than or equal to V1 according to the solution
        return DecimalMath.mul(V1, DecimalMath.ONE.add(premium));
    }
}

contract Pricing is Storage {
    using SafeMath for uint256;

    // ============ Query Functions ============

    function querySellBaseToken(
        address base,
        address quote,
        uint256 amount
    ) public view returns (uint256 receiveQuote) {
        // TODO: update prices from oracles

        (receiveQuote, , , ) = _querySellBaseToken(base, quote, amount);

        return receiveQuote;
    }

    function queryBuyBaseToken(
        address base,
        address quote,
        uint256 amount
    ) public view returns (uint256 payQuote) {
        // TODO: update prices from oracles

        (payQuote, , , ) = _queryBuyBaseToken(base, quote, amount);

        return payQuote;
    }

    // assumes prices are up-to-date
    function _querySellBaseToken(
        address base,
        address quote,
        uint256 amount
    )
        public
        view
        returns (
            uint256 receiveQuote,
            Types.RStatus newRStatus,
            uint256 newQuoteTarget,
            uint256 newBaseTarget
        )
    {
        // console.log("querySellBaseToken (base, quote, amount)"); //PRICE_DEBUG
        // console.log("querySellBaseToken (%s, %s, %s)", base, quote, amount); //PRICE_DEBUG

        (newBaseTarget, newQuoteTarget) = getExpectedTarget(base, quote);

        uint256 sellBaseAmount = amount;

        // console.log("_queryBuyBaseToken: R is %s", mapR(baseToken.RStatus));  //PRICE_DEBUG

        if (_records[base].RStatus == Types.RStatus.ONE) {
            // case 1: R=1
            // R falls below one
            receiveQuote = _ROneSellBaseToken(
                base,
                quote,
                sellBaseAmount,
                newQuoteTarget
            );
            newRStatus = Types.RStatus.BELOW_ONE;
        } else if (_records[base].RStatus == Types.RStatus.ABOVE_ONE) {
            uint256 backToOnePayBase =
                newBaseTarget.sub(_records[base].balance);
            uint256 backToOneReceiveQuote =
                _records[quote].balance.sub(newQuoteTarget);
            // case 2: R>1
            // complex case, R status depends on trading amount
            if (sellBaseAmount < backToOnePayBase) {
                // case 2.1: R status do not change
                receiveQuote = _RAboveSellBaseToken(
                    base,
                    quote,
                    _records[base].balance,
                    _records[base].balance,
                    newBaseTarget
                );
                newRStatus = Types.RStatus.ABOVE_ONE;
                if (receiveQuote > backToOneReceiveQuote) {
                    // [Important corner case!] may enter this branch when some precision problem happens. And consequently contribute to negative spare quote amount
                    // to make sure spare quote>=0, mannually set receiveQuote=backToOneReceiveQuote
                    receiveQuote = backToOneReceiveQuote;
                }
            } else if (sellBaseAmount == backToOnePayBase) {
                // case 2.2: R status changes to ONE
                receiveQuote = backToOneReceiveQuote;
                newRStatus = Types.RStatus.ONE;
            } else {
                // case 2.3: R status changes to BELOW_ONE
                receiveQuote = backToOneReceiveQuote.add(
                    _ROneSellBaseToken(
                        base,
                        quote,
                        sellBaseAmount.sub(backToOnePayBase),
                        newQuoteTarget
                    )
                );
                newRStatus = Types.RStatus.BELOW_ONE;
            }
        } else {
            // _R_STATUS_ == Types.RStatus.BELOW_ONE
            // case 3: R<1
            receiveQuote = _RBelowSellBaseToken(
                base,
                quote,
                sellBaseAmount,
                _records[quote].balance,
                newQuoteTarget
            );
            newRStatus = Types.RStatus.BELOW_ONE;
        }

        // console.log("querySellBaseToken: receiveQuote is %s", receiveQuote); //PRICE_DEBUG
        // console.log("querySellBaseToken: new R is %s", mapR(newRStatus)); //PRICE_DEBUG

        // return (receiveQuote, lpFeeQuote, mtFeeQuote, newRStatus, newQuoteTarget, newBaseTarget);
        return (receiveQuote, newRStatus, newQuoteTarget, newBaseTarget);
    }

    function _queryBuyBaseToken(
        address base,
        address quote,
        uint256 amount
    )
        public
        view
        returns (
            uint256 payQuote,
            Types.RStatus newRStatus,
            uint256 newQuoteTarget,
            uint256 newBaseTarget
        )
    {
        // console.log("_queryBuyBaseToken (base, quote, amount)"); //PRICE_DEBUG
        // console.log("_queryBuyBaseToken (%s, %s, %s)", base, quote, amount); //PRICE_DEBUG

        (newBaseTarget, newQuoteTarget) = getExpectedTarget(base, quote);

        // console.log("newBaseTarget is %s, newQuoteTarget is %s", newBaseTarget, newQuoteTarget); //PRICE_DEBUG

        // charge fee from user receive amount
        // lpFeeBase = DecimalMath.mul(amount, 0.3);
        // mtFeeBase = DecimalMath.mul(amount, _MT_FEE_RATE_);
        // uint256 buyBaseAmount = amount.add(lpFeeBase).add(mtFeeBase);
        uint256 buyBaseAmount = amount;

        // console.log("_queryBuyBaseToken: R is %s", getR(base)); //PRICE_DEBUG

        if (_records[base].RStatus == Types.RStatus.ONE) {
            // case 1: R=1
            payQuote = _ROneBuyBaseToken(
                base,
                quote,
                buyBaseAmount,
                newBaseTarget
            );

            newRStatus = Types.RStatus.ABOVE_ONE;
        } else if (_records[base].RStatus == Types.RStatus.ABOVE_ONE) {
            // case 2: R>1
            payQuote = _RAboveBuyBaseToken(
                base,
                quote,
                buyBaseAmount,
                _records[base].balance,
                newBaseTarget
            );
            newRStatus = Types.RStatus.ABOVE_ONE;
        } else if (_records[base].RStatus == Types.RStatus.BELOW_ONE) {
            uint256 backToOnePayQuote =
                newQuoteTarget.sub(_records[quote].balance);
            uint256 backToOneReceiveBase =
                _records[base].balance.sub(newBaseTarget);
            // case 3: R<1
            // complex case, R status may change
            if (buyBaseAmount < backToOneReceiveBase) {
                // case 3.1: R status do not change
                // no need to check payQuote because spare base token must be greater than zero
                payQuote = _RBelowBuyBaseToken(
                    base,
                    quote,
                    buyBaseAmount,
                    _records[quote].balance,
                    newQuoteTarget
                );
                newRStatus = Types.RStatus.BELOW_ONE;
            } else if (buyBaseAmount == backToOneReceiveBase) {
                // case 3.2: R status changes to ONE
                payQuote = backToOnePayQuote;
                newRStatus = Types.RStatus.ONE;
            } else {
                // case 3.3: R status changes to ABOVE_ONE
                payQuote = backToOnePayQuote.add(
                    _ROneBuyBaseToken(
                        base,
                        quote,
                        buyBaseAmount.sub(backToOneReceiveBase),
                        newBaseTarget
                    )
                );
                newRStatus = Types.RStatus.ABOVE_ONE;
            }
        }

        // console.log("_queryBuyBaseToken: payQuote is %s", payQuote); //PRICE_DEBUG
        // console.log("_queryBuyBaseToken: new R is %s", mapR(newRStatus)); //PRICE_DEBUG

        // return (payQuote, lpFeeBase, mtFeeBase, newRStatus, newQuoteTarget, newBaseTarget);
        return (payQuote, newRStatus, newQuoteTarget, newBaseTarget);
    }

    // ============ Pricing functions ============

    // ============ R = 1 cases ============

    function _ROneSellBaseToken(
        address base,
        address quote,
        uint256 amount,
        uint256 targetQuoteTokenAmount
    ) public view returns (uint256 receiveQuoteToken) {
        // console.log("ROneSellBaseToken (base, quote, amount, targetQuoteTokenAmount)"); //PRICE_DEBUG
        // console.log("ROneSellBaseToken (base, quote, %s, %s)", amount, targetQuoteTokenAmount); //PRICE_DEBUG

        uint256 i = getTransactionPrice(base, quote);
        // console.log("ROneSellBaseToken: Price is %s", i); //PRICE_DEBUG

        // console.log("SolveQuadraticFunctionForTrade (targetQuote, targetQuote, i*amount, false, k)"); //PRICE_DEBUG
        uint256 Q2 =
            DODOMath._SolveQuadraticFunctionForTrade(
                targetQuoteTokenAmount,
                targetQuoteTokenAmount,
                DecimalMath.mul(i, amount),
                false,
                _K_
            );

        // console.log("ROneSellBaseToken: receiveQuote is targetQuote - Q2"); //PRICE_DEBUG
        // console.log("ROneSellBaseToken: receiveQuote is %s - %s", targetQuoteTokenAmount, Q2); //PRICE_DEBUG
        // console.log("ROneSellBaseToken: receiveQuote is %s", targetQuoteTokenAmount.sub(Q2)); //PRICE_DEBUG
        // in theory Q2 <= targetQuoteTokenAmount
        // however when amount is close to 0, precision problems may cause Q2 > targetQuoteTokenAmount
        return targetQuoteTokenAmount.sub(Q2);
    }

    function _ROneBuyBaseToken(
        address base,
        address quote,
        uint256 amount,
        uint256 targetBaseTokenAmount
    ) public view returns (uint256 payQuoteToken) {
        // console.log("ROneBuyBaseToken  (base, quote, amount, targetBaseTokenAmount)"); //PRICE_DEBUG
        // console.log("ROneBuyBaseToken  (base, quote, %s, %s)", amount, targetBaseTokenAmount); //PRICE_DEBUG
        require(amount < targetBaseTokenAmount, "DODO_BASE_BALANCE_NOT_ENOUGH");
        uint256 B2 = targetBaseTokenAmount.sub(amount);

        // console.log("ROneBuyBaseToken:  New base balance is targetBaseTokenAmount - amount"); //PRICE_DEBUG
        // console.log("ROneBuyBaseToken:  New base balance is %s - %s", targetBaseTokenAmount, amount); //PRICE_DEBUG
        // console.log("ROneBuyBaseToken:  New base balance is %s", B2); //PRICE_DEBUG

        payQuoteToken = _RAboveIntegrate(
            base,
            quote,
            targetBaseTokenAmount,
            targetBaseTokenAmount,
            B2
        );
        return payQuoteToken;
    }

    // ============ R < 1 cases ============

    function _RBelowSellBaseToken(
        address base,
        address quote,
        uint256 amount,
        uint256 quoteBalance,
        uint256 targetQuoteAmount
    ) public view returns (uint256 receieQuoteToken) {
        uint256 i = getTransactionPrice(base, quote);
        uint256 Q2 =
            DODOMath._SolveQuadraticFunctionForTrade(
                targetQuoteAmount,
                quoteBalance,
                DecimalMath.mul(i, amount),
                false,
                _K_
            );
        return quoteBalance.sub(Q2);
    }

    function _RBelowBuyBaseToken(
        address base,
        address quote,
        uint256 amount,
        uint256 quoteBalance,
        uint256 targetQuoteAmount
    ) public view returns (uint256 payQuoteToken) {
        // Here we don't require amount less than some value
        // Because it is limited at upper function
        // See Trader._queryBuyBaseToken
        uint256 i = getTransactionPrice(base, quote);
        uint256 Q2 =
            DODOMath._SolveQuadraticFunctionForTrade(
                targetQuoteAmount,
                quoteBalance,
                DecimalMath.mulCeil(i, amount),
                true,
                _K_
            );
        return Q2.sub(quoteBalance);
    }

    function _RBelowBackToOne(address base, address quote)
        public
        view
        returns (uint256 payQuoteToken)
    {
        // important: carefully design the system to make sure spareBase always greater than or equal to 0
        uint256 spareBase = _records[base].balance.sub(_records[base].target);
        uint256 price = getTransactionPrice(base, quote);
        uint256 fairAmount = DecimalMath.mul(spareBase, price);
        uint256 newTargetQuote =
            DODOMath._SolveQuadraticFunctionForTarget(
                _records[base].balance,
                _K_,
                fairAmount
            );
        return newTargetQuote.sub(_records[quote].balance);
    }

    // ============ R > 1 cases ============

    function _RAboveBuyBaseToken(
        address base,
        address quote,
        uint256 amount,
        uint256 baseBalance,
        uint256 targetBaseAmount
    ) public view returns (uint256 payQuoteToken) {
        require(amount < baseBalance, "DODO_BASE_BALANCE_NOT_ENOUGH");
        uint256 B2 = baseBalance.sub(amount);
        return _RAboveIntegrate(base, quote, targetBaseAmount, baseBalance, B2);
    }

    function _RAboveSellBaseToken(
        address base,
        address quote,
        uint256 amount,
        uint256 baseBalance,
        uint256 targetBaseAmount
    ) public view returns (uint256 receiveQuoteToken) {
        // here we don't require B1 <= targetBaseAmount
        // Because it is limited at upper function
        // See Trader.querySellBaseToken
        uint256 B1 = baseBalance.add(amount);
        return _RAboveIntegrate(base, quote, targetBaseAmount, B1, baseBalance);
    }

    function _RAboveBackToOne(address base, address quote)
        public
        view
        returns (uint256 payBaseToken)
    {
        // important: carefully design the system to make sure spareBase always greater than or equal to 0
        uint256 spareQuote =
            _records[quote].balance.sub(_records[quote].target);
        uint256 price = getTransactionPrice(base, quote);
        uint256 fairAmount = DecimalMath.divFloor(spareQuote, price);
        uint256 newTargetBase =
            DODOMath._SolveQuadraticFunctionForTarget(
                _records[base].balance,
                _K_,
                fairAmount
            );
        return newTargetBase.sub(_records[base].balance);
    }

    // ============ Helper functions ============

    function getExpectedTarget(address base, address quote)
        public
        view
        returns (uint256 baseTarget, uint256 quoteTarget)
    {
        // console.log("getExpectedTarget (base, quote)"); //PRICE_DEBUG

        uint256 Q = _records[quote].balance;
        uint256 B = _records[base].balance;

        // console.log("getExpectedTarget: Base balance is %s, quote balance is %s", Q, B); //PRICE_DEBUG

        if (_records[base].RStatus == Types.RStatus.ONE) {
            // console.log("getExpectedTarget: Base target is  %s, quote target is  %s", baseToken.target, quoteToken.target); //PRICE_DEBUG

            return (_records[base].target, _records[base].target);
        } else if (_records[base].RStatus == Types.RStatus.BELOW_ONE) {
            uint256 payQuoteToken = _RBelowBackToOne(base, quote);
            return (_records[base].target, Q.add(payQuoteToken));
        } else if (_records[base].RStatus == Types.RStatus.ABOVE_ONE) {
            uint256 payBaseToken = _RAboveBackToOne(base, quote);
            return (B.add(payBaseToken), _records[base].target);
        }
    }

    function _RAboveIntegrate(
        address base,
        address quote,
        uint256 B0,
        uint256 B1,
        uint256 B2
    ) public view returns (uint256) {
        // console.log("RAboveIntegrate   (base, quote, B0, B1, B2)"); //PRICE_DEBUG
        // console.log("RAboveIntegrate   (base, quote, %s, %s, %s)", B0, B1, B2); //PRICE_DEBUG
        uint256 i = getTransactionPrice(base, quote);
        // console.log("RAboveIntegrate:   Price is %s", i); //PRICE_DEBUG
        return DODOMath._GeneralIntegrate(B0, B1, B2, i, _K_);
    }
}

contract Trading is Pricing {
    using SafeMath for uint256;

    // ============ Events ============

    event SellBaseToken(
        address indexed seller,
        uint256 payBase,
        uint256 receiveQuote
    );

    event BuyBaseToken(
        address indexed buyer,
        uint256 receiveBase,
        uint256 payQuote
    );

    event ChargeMaintainerFee(
        address indexed maintainer,
        bool isBaseToken,
        uint256 amount
    );

    // ============ Trade Functions ============

    function sellBaseToken(
        address base,
        address quote,
        uint256 amount,
        uint256 minReceiveQuote
    ) external preventReentrant returns (uint256) {
        // console.log("sellBaseToken (base, quote, amount, minReceiveQuote)"); //TRADE_DEBUG
        // console.log("sellBaseToken (base, quote, %s, %s)", amount, minReceiveQuote); //TRADE_DEBUG

        // TODO: update prices from oracles. Currently assumes prices are up-to-date.

        // query price
        (
            uint256 receiveQuote,
            // uint256 lpFeeQuote,
            // uint256 mtFeeQuote,
            Types.RStatus newRStatus,
            uint256 newQuoteTarget,
            uint256 newBaseTarget
        ) = _querySellBaseToken(base, quote, amount);
        // console.log("sellBaseToken: receiveQuote is %s", receiveQuote); //TRADE_DEBUG

        require(
            receiveQuote >= minReceiveQuote,
            "SELL_BASE_RECEIVE_NOT_ENOUGH"
        );

        // console.log("baseShare is %s, quoteShare is %s", getCurrentShare(base), getCurrentShare(quote)); // ORACLE_DEBUG

        updatePortfolioValue();

        checkSharesAfterTx(
            base,
            quote,
            _records[base].balance + amount,
            _records[quote].balance - receiveQuote
        );

        // console.log("baseShare will be %s, quoteShare will be %s", baseShare, quoteShare); // ORACLE_DEBUG

        // settle assets
        _quoteTokenTransferOut(quote, msg.sender, receiveQuote);

        _baseTokenTransferIn(base, msg.sender, amount);

        // update TARGET
        if (_records[quote].target != newQuoteTarget) {
            _records[quote].target = newQuoteTarget;
        }
        if (_records[base].target != newBaseTarget) {
            _records[base].target = newBaseTarget;
        }
        if (_records[base].RStatus != newRStatus) {
            _records[base].RStatus = newRStatus;
        }

        // _donateQuoteToken(lpFeeQuote);
        emit SellBaseToken(msg.sender, amount, receiveQuote);

        return receiveQuote;
    }

    function buyBaseToken(
        address base,
        address quote,
        uint256 amount,
        uint256 maxPayQuote
    ) external preventReentrant returns (uint256) {
        // TODO: update prices from oracles. Currently assumes prices are up-to-date.

        // query price
        (
            uint256 payQuote,
            Types.RStatus newRStatus,
            uint256 newQuoteTarget,
            uint256 newBaseTarget
        ) = _queryBuyBaseToken(base, quote, amount);
        require(payQuote <= maxPayQuote, "BUY_BASE_COST_TOO_MUCH");

        updatePortfolioValue();

        checkSharesAfterTx(
            quote,
            base,
            _records[quote].balance + payQuote,
            _records[base].balance - amount
        );

        // settle assets
        _baseTokenTransferOut(base, msg.sender, amount);

        _quoteTokenTransferIn(quote, msg.sender, payQuote);

        // update TARGET
        if (_records[quote].target != newQuoteTarget) {
            _records[quote].target = newQuoteTarget;
        }
        if (_records[base].target != newBaseTarget) {
            _records[base].target = newBaseTarget;
        }
        if (_records[base].RStatus != newRStatus) {
            _records[base].RStatus = newRStatus;
        }

        // _donateBaseToken(lpFeeBase);
        emit BuyBaseToken(msg.sender, amount, payQuote);

        return payQuote;
    }

    // ============ Assets IN/OUT Functions ============

    function _baseTokenTransferIn(
        address base,
        address from,
        uint256 amount
    ) public {
        // console.log("_baseTokenTransferIn (base, from, amount)"); //TRADE_DEBUG

        require(
            _records[base].balance.add(amount) <= _records[base].balanceLimit,
            "BASE_BALANCE_LIMIT_EXCEEDED"
        );
        IERC20(base).transferFrom(from, address(this), amount);
        _records[base].balance = _records[base].balance.add(amount);
        // console.log("_baseTokenTransferIn baseBalance is %s", baseToken.balance); //TRADE_DEBUG
    }

    function _quoteTokenTransferIn(
        address quote,
        address from,
        uint256 amount
    ) public {
        // console.log("_quoteTokenTransferIn (quote, from, amount)"); //TRADE_DEBUG

        require(
            _records[quote].balance.add(amount) <= _records[quote].balanceLimit,
            "QUOTE_BALANCE_LIMIT_EXCEEDED"
        );
        IERC20(quote).transferFrom(from, address(this), amount);
        _records[quote].balance = _records[quote].balance.add(amount);
    }

    function _baseTokenTransferOut(
        address base,
        address to,
        uint256 amount
    ) public {
        // console.log("_baseTokenTransferOut (base, to, amount)"); //TRADE_DEBUG

        IERC20(base).transfer(to, amount);
        _records[base].balance = _records[base].balance.sub(amount);
    }

    function _quoteTokenTransferOut(
        address quote,
        address to,
        uint256 amount
    ) public {
        // console.log("_quoteTokenTransferOut (quote, to, amount)"); //TRADE_DEBUG
        IERC20(quote).transfer(to, amount);
        _records[quote].balance = _records[quote].balance.sub(amount);
        // console.log("_quoteTokenTransferOut quoteBalance is %s", quoteToken.balance); //TRADE_DEBUG
    }
}

contract LiquidityProvider is Storage, LPToken {
    using SafeMath for uint256;

    event LOG_SWAP(
        address indexed caller,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 tokenAmountIn,
        uint256 tokenAmountOut
    );

    event LOG_JOIN(
        address indexed caller,
        address indexed tokenIn,
        uint256 tokenAmountIn
    );

    event LOG_EXIT(
        address indexed caller,
        address indexed tokenOut,
        uint256 tokenAmountOut
    );

    // Absorb any tokens that have been sent to this contract into the pool
    function gulp(address token) external _logs_ _lock_ {
        require(_records[token].bound, "ERR_NOT_BOUND");
        _records[token].balance = IERC20(token).balanceOf(address(this));
    }

    function joinPool(uint256 poolAmountOut, uint256[] calldata maxAmountsIn)
        external
        _logs_
        _lock_
    {
        require(_finalized, "ERR_NOT_FINALIZED");

        uint256 poolTotal = totalSupply();
        uint256 ratio = bdiv(poolAmountOut, poolTotal);
        require(ratio != 0, "ERR_MATH_APPROX");

        for (uint256 i = 0; i < _tokens.length; i++) {
            address t = _tokens[i];
            uint256 bal = _records[t].balance;
            uint256 tokenAmountIn = bmul(ratio, bal);
            require(tokenAmountIn != 0, "ERR_MATH_APPROX");
            require(tokenAmountIn <= maxAmountsIn[i], "ERR_LIMIT_IN");
            _records[t].balance = badd(_records[t].balance, tokenAmountIn);
            emit LOG_JOIN(msg.sender, t, tokenAmountIn);
            _pullUnderlying(t, msg.sender, tokenAmountIn);
        }
        _mintPoolShare(poolAmountOut);
        _pushPoolShare(msg.sender, poolAmountOut);
    }

    function exitPool(uint256 poolAmountIn, uint256[] calldata minAmountsOut)
        external
        _logs_
        _lock_
    {
        require(_finalized, "ERR_NOT_FINALIZED");

        uint256 poolTotal = totalSupply();
        uint256 exitFee = bmul(poolAmountIn, EXIT_FEE);
        uint256 pAiAfterExitFee = bsub(poolAmountIn, exitFee);
        uint256 ratio = bdiv(pAiAfterExitFee, poolTotal);
        require(ratio != 0, "ERR_MATH_APPROX");

        _pullPoolShare(msg.sender, poolAmountIn);
        _pushPoolShare(_factory, exitFee);
        _burnPoolShare(pAiAfterExitFee);

        for (uint256 i = 0; i < _tokens.length; i++) {
            address t = _tokens[i];
            uint256 bal = _records[t].balance;
            uint256 tokenAmountOut = bmul(ratio, bal);
            require(tokenAmountOut != 0, "ERR_MATH_APPROX");
            require(tokenAmountOut >= minAmountsOut[i], "ERR_LIMIT_OUT");
            _records[t].balance = bsub(_records[t].balance, tokenAmountOut);
            emit LOG_EXIT(msg.sender, t, tokenAmountOut);
            _pushUnderlying(t, msg.sender, tokenAmountOut);
        }
    }

    function joinswapExternAmountIn(
        address tokenIn,
        uint256 tokenAmountIn,
        uint256 minPoolAmountOut
    ) external _logs_ _lock_ returns (uint256 poolAmountOut) {
        require(_finalized, "ERR_NOT_FINALIZED");
        require(_records[tokenIn].bound, "ERR_NOT_BOUND");
        require(
            tokenAmountIn <= bmul(_records[tokenIn].balance, MAX_IN_RATIO),
            "ERR_MAX_IN_RATIO"
        );

        Record storage inRecord = _records[tokenIn];

        poolAmountOut = tokenAmountIn;

        require(poolAmountOut >= minPoolAmountOut, "ERR_LIMIT_OUT");

        inRecord.balance = badd(inRecord.balance, tokenAmountIn);

        emit LOG_JOIN(msg.sender, tokenIn, tokenAmountIn);

        _mintPoolShare(poolAmountOut);
        _pushPoolShare(msg.sender, poolAmountOut);
        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);

        return poolAmountOut;
    }

    function joinswapPoolAmountOut(
        address tokenIn,
        uint256 poolAmountOut,
        uint256 maxAmountIn
    ) external _logs_ _lock_ returns (uint256 tokenAmountIn) {
        require(_finalized, "ERR_NOT_FINALIZED");
        require(_records[tokenIn].bound, "ERR_NOT_BOUND");

        Record storage inRecord = _records[tokenIn];

        tokenAmountIn = poolAmountOut;

        require(tokenAmountIn != 0, "ERR_MATH_APPROX");
        require(tokenAmountIn <= maxAmountIn, "ERR_LIMIT_IN");

        require(
            tokenAmountIn <= bmul(_records[tokenIn].balance, MAX_IN_RATIO),
            "ERR_MAX_IN_RATIO"
        );

        inRecord.balance = badd(inRecord.balance, tokenAmountIn);

        emit LOG_JOIN(msg.sender, tokenIn, tokenAmountIn);

        _mintPoolShare(poolAmountOut);
        _pushPoolShare(msg.sender, poolAmountOut);
        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);

        return tokenAmountIn;
    }

    function exitswapPoolAmountIn(
        address tokenOut,
        uint256 poolAmountIn,
        uint256 minAmountOut
    ) external _logs_ _lock_ returns (uint256 tokenAmountOut) {
        require(_finalized, "ERR_NOT_FINALIZED");
        require(_records[tokenOut].bound, "ERR_NOT_BOUND");

        Record storage outRecord = _records[tokenOut];

        tokenAmountOut = poolAmountIn;

        require(tokenAmountOut >= minAmountOut, "ERR_LIMIT_OUT");

        require(
            tokenAmountOut <= bmul(_records[tokenOut].balance, MAX_OUT_RATIO),
            "ERR_MAX_OUT_RATIO"
        );

        outRecord.balance = bsub(outRecord.balance, tokenAmountOut);

        uint256 exitFee = bmul(poolAmountIn, EXIT_FEE);

        emit LOG_EXIT(msg.sender, tokenOut, tokenAmountOut);

        _pullPoolShare(msg.sender, poolAmountIn);
        _burnPoolShare(bsub(poolAmountIn, exitFee));
        _pushPoolShare(_factory, exitFee);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);

        return tokenAmountOut;
    }

    function exitswapExternAmountOut(
        address tokenOut,
        uint256 tokenAmountOut,
        uint256 maxPoolAmountIn
    ) external _logs_ _lock_ returns (uint256 poolAmountIn) {
        require(_finalized, "ERR_NOT_FINALIZED");
        require(_records[tokenOut].bound, "ERR_NOT_BOUND");
        require(
            tokenAmountOut <= bmul(_records[tokenOut].balance, MAX_OUT_RATIO),
            "ERR_MAX_OUT_RATIO"
        );

        Record storage outRecord = _records[tokenOut];

        poolAmountIn = tokenAmountOut;

        require(poolAmountIn != 0, "ERR_MATH_APPROX");
        require(poolAmountIn <= maxPoolAmountIn, "ERR_LIMIT_IN");

        outRecord.balance = bsub(outRecord.balance, tokenAmountOut);

        uint256 exitFee = bmul(poolAmountIn, EXIT_FEE);

        emit LOG_EXIT(msg.sender, tokenOut, tokenAmountOut);

        _pullPoolShare(msg.sender, poolAmountIn);
        _burnPoolShare(bsub(poolAmountIn, exitFee));
        _pushPoolShare(_factory, exitFee);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);

        return poolAmountIn;
    }
}

contract PFOLIO is LiquidityProvider, Trading, Admin {
    constructor() public {
        _controller = msg.sender;
        _factory = msg.sender;
        _swapFee = MIN_FEE;
        _publicSwap = false;
        _finalized = false;
        _K_ = 10**17;
        _SUPERVISOR_ = msg.sender; // could freeze system in emergency
        _MAINTAINER_ = msg.sender; // collect maintainer fee to buy food for DODO
    }
}

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

    function mulCeil(uint256 target, uint256 d) internal pure returns (uint256) {
        return target.mul(d).divCeil(ONE);
    }

    function divFloor(uint256 target, uint256 d) internal pure returns (uint256) {
        return target.mul(ONE).div(d);
    }

    function divCeil(uint256 target, uint256 d) internal pure returns (uint256) {
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
        uint256 squareRoot = DecimalMath.mul(
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
        uint256 sqrt = DecimalMath.divCeil(DecimalMath.mul(k, fairAmount).mul(4), V1);
        sqrt = sqrt.add(DecimalMath.ONE).mul(DecimalMath.ONE).sqrt();
        uint256 premium = DecimalMath.divCeil(sqrt.sub(DecimalMath.ONE), k.mul(2));
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
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
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
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
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
        //  1. The target address is checked to verify it contains contract code
        //  2. The call itself is made, and success asserted
        //  3. The return value is decoded, which in turn checks the size of the returned data.
        // solhint-disable-next-line max-line-length

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeERC20: low-level call failed");

        if (returndata.length > 0) {
            // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
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
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

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
    uint public constant BONE              = 10**18;

    uint public constant MIN_BOUND_TOKENS  = 2;
    uint public constant MAX_BOUND_TOKENS  = 8;

    uint public constant MIN_FEE           = BONE / 10**6;
    uint public constant MAX_FEE           = BONE / 10;
    uint public constant EXIT_FEE          = 0;

    uint public constant MIN_WEIGHT        = BONE;
    uint public constant MAX_WEIGHT        = BONE * 50;
    uint public constant MAX_TOTAL_WEIGHT  = BONE * 50;
    uint public constant MIN_BALANCE       = BONE / 10**12;

    uint public constant INIT_POOL_SUPPLY  = BONE * 100;

    uint public constant MIN_BPOW_BASE     = 1 wei;
    uint public constant MAX_BPOW_BASE     = (2 * BONE) - 1 wei;
    uint public constant BPOW_PRECISION    = BONE / 10**10;

    uint public constant MAX_IN_RATIO      = BONE / 2;
    uint public constant MAX_OUT_RATIO     = (BONE / 3) + 1 wei;

    uint256 MAX_INT = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

}

contract BNum is BConst {

    function btoi(uint a)
        internal pure
        returns (uint)
    {
        return a / BONE;
    }

    function bfloor(uint a)
        internal pure
        returns (uint)
    {
        return btoi(a) * BONE;
    }

    function badd(uint a, uint b)
        internal pure
        returns (uint)
    {
        uint c = a + b;
        require(c >= a, "ERR_ADD_OVERFLOW");
        return c;
    }

    function bsub(uint a, uint b)
        internal pure
        returns (uint)
    {
        (uint c, bool flag) = bsubSign(a, b);
        require(!flag, "ERR_SUB_UNDERFLOW");
        return c;
    }

    function bsubSign(uint a, uint b)
        internal pure
        returns (uint, bool)
    {
        if (a >= b) {
            return (a - b, false);
        } else {
            return (b - a, true);
        }
    }

    function bmul(uint a, uint b)
        internal pure
        returns (uint)
    {
        uint c0 = a * b;
        require(a == 0 || c0 / a == b, "ERR_MUL_OVERFLOW");
        uint c1 = c0 + (BONE / 2);
        require(c1 >= c0, "ERR_MUL_OVERFLOW");
        uint c2 = c1 / BONE;
        return c2;
    }

    function bdiv(uint a, uint b)
        internal pure
        returns (uint)
    {
        require(b != 0, "ERR_DIV_ZERO");
        uint c0 = a * BONE;
        require(a == 0 || c0 / a == BONE, "ERR_DIV_INTERNAL"); // bmul overflow
        uint c1 = c0 + (b / 2);
        require(c1 >= c0, "ERR_DIV_INTERNAL"); //  badd require
        uint c2 = c1 / b;
        return c2;
    }

    // DSMath.wpow
    function bpowi(uint a, uint n)
        internal pure
        returns (uint)
    {
        uint z = n % 2 != 0 ? a : BONE;

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
    function bpow(uint base, uint exp)
        internal pure
        returns (uint)
    {
        require(base >= MIN_BPOW_BASE, "ERR_BPOW_BASE_TOO_LOW");
        require(base <= MAX_BPOW_BASE, "ERR_BPOW_BASE_TOO_HIGH");

        uint whole  = bfloor(exp);
        uint remain = bsub(exp, whole);

        uint wholePow = bpowi(base, btoi(whole));

        if (remain == 0) {
            return wholePow;
        }

        uint partialResult = bpowApprox(base, remain, BPOW_PRECISION);
        return bmul(wholePow, partialResult);
    }

    function bpowApprox(uint base, uint exp, uint precision)
        internal pure
        returns (uint)
    {
        // term 0:
        uint a     = exp;
        (uint x, bool xneg)  = bsubSign(base, BONE);
        uint term = BONE;
        uint sum   = term;
        bool negative = false;


        // term(k) = numer / denom
        //         = (product(a - i - 1, i=1-->k) * x^k) / (k!)
        // each iteration, multiply previous term by (a-(k-1)) * x / k
        // continue until term is less than precision
        for (uint i = 1; term >= precision; i++) {
            uint bigK = i * BONE;
            (uint c, bool cneg) = bsubSign(a, bsub(bigK, BONE));
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

// interface IERC20 {
//     event Approval(address indexed src, address indexed dst, uint amt);
//     event Transfer(address indexed src, address indexed dst, uint amt);

//     function totalSupply() external view returns (uint);
//     function balanceOf(address whom) external view returns (uint);
//     function allowance(address src, address dst) external view returns (uint);

//     function approve(address dst, uint amt) external returns (bool);
//     function transfer(address dst, uint amt) external returns (bool);
//     function transferFrom(
//         address src, address dst, uint amt
//     ) external returns (bool);
// }

contract BTokenBase is BNum {

    mapping(address => uint)                   internal _balance;
    mapping(address => mapping(address=>uint)) internal _allowance;
    uint internal _totalSupply;

    event Approval(address indexed src, address indexed dst, uint amt);
    event Transfer(address indexed src, address indexed dst, uint amt);

    function _mint(uint amt) internal {
        _balance[address(this)] = badd(_balance[address(this)], amt);
        _totalSupply = badd(_totalSupply, amt);
        emit Transfer(address(0), address(this), amt);
    }

    function _burn(uint amt) internal {
        require(_balance[address(this)] >= amt, "ERR_INSUFFICIENT_BAL");
        _balance[address(this)] = bsub(_balance[address(this)], amt);
        _totalSupply = bsub(_totalSupply, amt);
        emit Transfer(address(this), address(0), amt);
    }

    function _move(address src, address dst, uint amt) internal {
        require(_balance[src] >= amt, "ERR_INSUFFICIENT_BAL");
        _balance[src] = bsub(_balance[src], amt);
        _balance[dst] = badd(_balance[dst], amt);
        emit Transfer(src, dst, amt);
    }

    function _push(address to, uint amt) internal {
        _move(address(this), to, amt);
    }

    function _pull(address from, uint amt) internal {
        _move(from, address(this), amt);
    }
}

contract BToken is BTokenBase, IERC20 {

    string  private _name     = "Balancer Pool Token";
    string  private _symbol   = "BPT";
    uint8   private _decimals = 18;

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns(uint8) {
        return _decimals;
    }

    function allowance(address src, address dst) external view override returns (uint) {
        return _allowance[src][dst];
    }

    function balanceOf(address whom) external view override returns (uint) {
        return _balance[whom];
    }

    function totalSupply() public view override returns (uint) {
        return _totalSupply;
    }

    function approve(address dst, uint amt) external override returns (bool) {
        _allowance[msg.sender][dst] = amt;
        emit Approval(msg.sender, dst, amt);
        return true;
    }

    function increaseApproval(address dst, uint amt) external returns (bool) {
        _allowance[msg.sender][dst] = badd(_allowance[msg.sender][dst], amt);
        emit Approval(msg.sender, dst, _allowance[msg.sender][dst]);
        return true;
    }

    function decreaseApproval(address dst, uint amt) external returns (bool) {
        uint oldValue = _allowance[msg.sender][dst];
        if (amt > oldValue) {
            _allowance[msg.sender][dst] = 0;
        } else {
            _allowance[msg.sender][dst] = bsub(oldValue, amt);
        }
        emit Approval(msg.sender, dst, _allowance[msg.sender][dst]);
        return true;
    }

    function transfer(address dst, uint amt) external override returns (bool) {
        _move(msg.sender, dst, amt);
        return true;
    }

    function transferFrom(address src, address dst, uint amt) external override returns (bool) {
        require(msg.sender == src || amt <= _allowance[src][msg.sender], "ERR_BTOKEN_BAD_CALLER");
        _move(src, dst, amt);
        if (msg.sender != src && _allowance[src][msg.sender] != uint256(-1)) {
            _allowance[src][msg.sender] = bsub(_allowance[src][msg.sender], amt);
            emit Approval(msg.sender, dst, _allowance[src][msg.sender]);
        }
        return true;
    }
}

contract PFOLIO is BToken {
    using SafeMath for uint256;

    // struct Record {
    //     bool bound;   // is token bound to pool
    //     uint index;   // private
    //     uint denorm;  // denormalized weight
    //     uint balance;
    //     Types.RStatus RStatus;
    //     uint targetTokenAmount;
    //     uint balanceLimit;
    // }

    event LOG_SWAP(
        address indexed caller,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256         tokenAmountIn,
        uint256         tokenAmountOut
    );

    event LOG_JOIN(
        address indexed caller,
        address indexed tokenIn,
        uint256         tokenAmountIn
    );

    event LOG_EXIT(
        address indexed caller,
        address indexed tokenOut,
        uint256         tokenAmountOut
    );

    event LOG_CALL(
        bytes4  indexed sig,
        address indexed caller,
        bytes           data
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

    address private _factory;    // BFactory address to push token exitFee to
    address private _controller; // has CONTROL role
    bool private _publicSwap; // true if PUBLIC can call SWAP functions

    // `setSwapFee` and `finalize` require CONTROL
    // `finalize` sets `PUBLIC can SWAP`, `PUBLIC can JOIN`
    uint private _swapFee;
    bool private _finalized;

    address[] private _tokens;

    mapping(address=>Record) private  _records;

    uint private _totalWeight;

    constructor() public {
        _controller = msg.sender;
        _factory = msg.sender;
        _swapFee = MIN_FEE;
        _publicSwap = false;
        _finalized = false;
        _LP_FEE_RATE_ = MIN_FEE;
        _MT_FEE_RATE_ = MIN_FEE;
        _K_ = 10**17;
        _SUPERVISOR_ = msg.sender; // could freeze system in emergency
        _MAINTAINER_ = msg.sender; // collect maintainer fee to buy food for DODO
    }

    function isPublicSwap()
        external view
        returns (bool)
    {
        return _publicSwap;
    }

    function isFinalized()
        external view
        returns (bool)
    {
        return _finalized;
    }

    function isBound(address t)
        external view
        returns (bool)
    {
        return _records[t].bound;
    }

    function getNumTokens()
        external view
        returns (uint)
    {
        return _tokens.length;
    }

    function getCurrentTokens()
        external view _viewlock_
        returns (address[] memory tokens)
    {
        return _tokens;
    }

    function getFinalTokens()
        external view
        _viewlock_
        returns (address[] memory tokens)
    {
        require(_finalized, "ERR_NOT_FINALIZED");
        return _tokens;
    }

    function getDenormalizedWeight(address token)
        external view
        _viewlock_
        returns (uint)
    {

        require(_records[token].bound, "ERR_NOT_BOUND");
        return _records[token].denorm;
    }

    function getTotalDenormalizedWeight()
        external view
        _viewlock_
        returns (uint)
    {
        return _totalWeight;
    }

    function getNormalizedWeight(address token)
        external view
        _viewlock_
        returns (uint)
    {

        require(_records[token].bound, "ERR_NOT_BOUND");
        uint denorm = _records[token].denorm;
        return bdiv(denorm, _totalWeight);
    }

    function getBalance(address token)
        external view
        _viewlock_
        returns (uint)
    {

        require(_records[token].bound, "ERR_NOT_BOUND");
        return _records[token].balance;
    }

    function getSwapFee()
        external view
        _viewlock_
        returns (uint)
    {
        return _swapFee;
    }

    function getController()
        external view
        _viewlock_
        returns (address)
    {
        return _controller;
    }

    function setSwapFee(uint swapFee)
        external
        _logs_
        _lock_
    {
        require(!_finalized, "ERR_IS_FINALIZED");
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        require(swapFee >= MIN_FEE, "ERR_MIN_FEE");
        require(swapFee <= MAX_FEE, "ERR_MAX_FEE");
        _swapFee = swapFee;
    }

    function setController(address manager)
        external
        _logs_
        _lock_
    {
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        _controller = manager;
    }

    function setPublicSwap(bool public_)
        external
        _logs_
        _lock_
    {
        require(!_finalized, "ERR_IS_FINALIZED");
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        _publicSwap = public_;
    }

    function finalize()
        external
        _logs_
        _lock_
    {
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        require(!_finalized, "ERR_IS_FINALIZED");
        require(_tokens.length >= MIN_BOUND_TOKENS, "ERR_MIN_TOKENS");

        _finalized = true;
        _publicSwap = true;

        _mintPoolShare(INIT_POOL_SUPPLY);
        _pushPoolShare(msg.sender, INIT_POOL_SUPPLY);
    }


    function bind(address token, uint balance, uint denorm)
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
            denorm: 0,    // balance and denorm will be validated
            balance: 0,   // and set by `rebind`
            RStatus: Types.RStatus.ONE,
            targetTokenAmount: 0,
            balanceLimit: MAX_INT,
            token: token
        });
        _tokens.push(token);
        rebind(token, balance, denorm);
    }
    
    function setOraclePrice(address base, address quote, uint256 price) external returns (uint256)
    
    {
        _oracles[base][quote] = price;
        return _oracles[base][quote];
    }
        
    function setK(uint256 k) external returns (uint256)
    
    {
        _K_ = k;
        return k;
    }

    function getQuadratic(
        uint256 targetQuoteTokenAmount,
        uint256 i,
        uint256 amount,
        uint256 k
    ) external pure returns (uint256) {
        uint256 Q2 = DODOMath._SolveQuadraticFunctionForTrade(
            targetQuoteTokenAmount,
            targetQuoteTokenAmount,
            DecimalMath.mul(i, amount),
            false,
            k
        );
        return Q2;
    }

    function rebind(address token, uint balance, uint denorm)
        public
        _logs_
        _lock_
    {

        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        require(_records[token].bound, "ERR_NOT_BOUND");
        require(!_finalized, "ERR_IS_FINALIZED");

        require(denorm >= MIN_WEIGHT, "ERR_MIN_WEIGHT");
        require(denorm <= MAX_WEIGHT, "ERR_MAX_WEIGHT");
        require(balance >= MIN_BALANCE, "ERR_MIN_BALANCE");

        // Adjust the denorm and totalWeight
        uint oldWeight = _records[token].denorm;
        if (denorm > oldWeight) {
            _totalWeight = badd(_totalWeight, bsub(denorm, oldWeight));
            require(_totalWeight <= MAX_TOTAL_WEIGHT, "ERR_MAX_TOTAL_WEIGHT");
        } else if (denorm < oldWeight) {
            _totalWeight = bsub(_totalWeight, bsub(oldWeight, denorm));
        }
        _records[token].denorm = denorm;

        // Adjust the balance record and actual token balance
        uint oldBalance = _records[token].balance;
        _records[token].balance = balance;
        _records[token].targetTokenAmount = balance;
        if (balance > oldBalance) {
            _pullUnderlying(token, msg.sender, bsub(balance, oldBalance));
        } else if (balance < oldBalance) {
            // In this case liquidity is being withdrawn, so charge EXIT_FEE
            uint tokenBalanceWithdrawn = bsub(oldBalance, balance);
            uint tokenExitFee = bmul(tokenBalanceWithdrawn, EXIT_FEE);
            _pushUnderlying(token, msg.sender, bsub(tokenBalanceWithdrawn, tokenExitFee));
            _pushUnderlying(token, _factory, tokenExitFee);
        }
    }

    function unbind(address token)
        external
        _logs_
        _lock_
    {

        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        require(_records[token].bound, "ERR_NOT_BOUND");
        require(!_finalized, "ERR_IS_FINALIZED");

        uint tokenBalance = _records[token].balance;
        uint tokenExitFee = bmul(tokenBalance, EXIT_FEE);

        _totalWeight = bsub(_totalWeight, _records[token].denorm);

        // Swap the token-to-unbind with the last token,
        // then delete the last token
        uint index = _records[token].index;
        uint last = _tokens.length - 1;
        _tokens[index] = _tokens[last];
        _records[_tokens[index]].index = index;
        _tokens.pop();
        _records[token] = Record({
            bound: false,
            index: 0,
            denorm: 0,
            balance: 0,
            RStatus: Types.RStatus.ONE,
            targetTokenAmount: 0,
            balanceLimit: MAX_INT,
            token: token
        });

        _pushUnderlying(token, msg.sender, bsub(tokenBalance, tokenExitFee));
        _pushUnderlying(token, _factory, tokenExitFee);
    }

    // Absorb any tokens that have been sent to this contract into the pool
    function gulp(address token)
        external
        _logs_
        _lock_
    {
        require(_records[token].bound, "ERR_NOT_BOUND");
        _records[token].balance = IERC20(token).balanceOf(address(this));
    }

    // function getSpotPrice(address tokenIn, address tokenOut)
    //     external view
    //     _viewlock_
    //     returns (uint spotPrice)
    // {
    //     require(_records[tokenIn].bound, "ERR_NOT_BOUND");
    //     require(_records[tokenOut].bound, "ERR_NOT_BOUND");
    //     Record storage inRecord = _records[tokenIn];
    //     Record storage outRecord = _records[tokenOut];
    //     return calcSpotPrice(inRecord.balance, inRecord.denorm, outRecord.balance, outRecord.denorm, _swapFee);
    // }

    // function getSpotPriceSansFee(address tokenIn, address tokenOut)
    //     external view
    //     _viewlock_
    //     returns (uint spotPrice)
    // {
    //     require(_records[tokenIn].bound, "ERR_NOT_BOUND");
    //     require(_records[tokenOut].bound, "ERR_NOT_BOUND");
    //     Record storage inRecord = _records[tokenIn];
    //     Record storage outRecord = _records[tokenOut];
    //     return calcSpotPrice(inRecord.balance, inRecord.denorm, outRecord.balance, outRecord.denorm, 0);
    // }

    function joinPool(uint poolAmountOut, uint[] calldata maxAmountsIn)
        external
        _logs_
        _lock_
    {
        require(_finalized, "ERR_NOT_FINALIZED");

        uint poolTotal = totalSupply();
        uint ratio = bdiv(poolAmountOut, poolTotal);
        require(ratio != 0, "ERR_MATH_APPROX");

        for (uint i = 0; i < _tokens.length; i++) {
            address t = _tokens[i];
            uint bal = _records[t].balance;
            uint tokenAmountIn = bmul(ratio, bal);
            require(tokenAmountIn != 0, "ERR_MATH_APPROX");
            require(tokenAmountIn <= maxAmountsIn[i], "ERR_LIMIT_IN");
            _records[t].balance = badd(_records[t].balance, tokenAmountIn);
            emit LOG_JOIN(msg.sender, t, tokenAmountIn);
            _pullUnderlying(t, msg.sender, tokenAmountIn);
        }
        _mintPoolShare(poolAmountOut);
        _pushPoolShare(msg.sender, poolAmountOut);
    }

    function exitPool(uint poolAmountIn, uint[] calldata minAmountsOut)
        external
        _logs_
        _lock_
    {
        require(_finalized, "ERR_NOT_FINALIZED");

        uint poolTotal = totalSupply();
        uint exitFee = bmul(poolAmountIn, EXIT_FEE);
        uint pAiAfterExitFee = bsub(poolAmountIn, exitFee);
        uint ratio = bdiv(pAiAfterExitFee, poolTotal);
        require(ratio != 0, "ERR_MATH_APPROX");

        _pullPoolShare(msg.sender, poolAmountIn);
        _pushPoolShare(_factory, exitFee);
        _burnPoolShare(pAiAfterExitFee);

        for (uint i = 0; i < _tokens.length; i++) {
            address t = _tokens[i];
            uint bal = _records[t].balance;
            uint tokenAmountOut = bmul(ratio, bal);
            require(tokenAmountOut != 0, "ERR_MATH_APPROX");
            require(tokenAmountOut >= minAmountsOut[i], "ERR_LIMIT_OUT");
            _records[t].balance = bsub(_records[t].balance, tokenAmountOut);
            emit LOG_EXIT(msg.sender, t, tokenAmountOut);
            _pushUnderlying(t, msg.sender, tokenAmountOut);
        }

    }


    // function swapExactAmountIn(
    //     address tokenIn,
    //     uint tokenAmountIn,
    //     address tokenOut,
    //     uint minAmountOut,
    //     uint maxPrice
    // )
    //     external
    //     _logs_
    //     _lock_
    //     returns (uint tokenAmountOut, uint spotPriceAfter)
    // {

    //     require(_records[tokenIn].bound, "ERR_NOT_BOUND");
    //     require(_records[tokenOut].bound, "ERR_NOT_BOUND");
    //     require(_publicSwap, "ERR_SWAP_NOT_PUBLIC");

    //     Record storage inRecord = _records[address(tokenIn)];
    //     Record storage outRecord = _records[address(tokenOut)];

    //     require(tokenAmountIn <= bmul(inRecord.balance, MAX_IN_RATIO), "ERR_MAX_IN_RATIO");

    //     uint spotPriceBefore = calcSpotPrice(
    //                                 inRecord.balance,
    //                                 inRecord.denorm,
    //                                 outRecord.balance,
    //                                 outRecord.denorm,
    //                                 _swapFee
    //                             );
    //     require(spotPriceBefore <= maxPrice, "ERR_BAD_LIMIT_PRICE");

    //     tokenAmountOut = calcOutGivenIn(
    //                         inRecord.balance,
    //                         inRecord.denorm,
    //                         outRecord.balance,
    //                         outRecord.denorm,
    //                         tokenAmountIn,
    //                         _swapFee
    //                     );
    //     require(tokenAmountOut >= minAmountOut, "ERR_LIMIT_OUT");

    //     inRecord.balance = badd(inRecord.balance, tokenAmountIn);
    //     outRecord.balance = bsub(outRecord.balance, tokenAmountOut);

    //     spotPriceAfter = calcSpotPrice(
    //                             inRecord.balance,
    //                             inRecord.denorm,
    //                             outRecord.balance,
    //                             outRecord.denorm,
    //                             _swapFee
    //                         );
    //     require(spotPriceAfter >= spotPriceBefore, "ERR_MATH_APPROX");
    //     require(spotPriceAfter <= maxPrice, "ERR_LIMIT_PRICE");
    //     require(spotPriceBefore <= bdiv(tokenAmountIn, tokenAmountOut), "ERR_MATH_APPROX");

    //     emit LOG_SWAP(msg.sender, tokenIn, tokenOut, tokenAmountIn, tokenAmountOut);

    //     _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);
    //     _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);

    //     return (tokenAmountOut, spotPriceAfter);
    // }

    // function swapExactAmountOut(
    //     address tokenIn,
    //     uint maxAmountIn,
    //     address tokenOut,
    //     uint tokenAmountOut,
    //     uint maxPrice
    // )
    //     external
    //     _logs_
    //     _lock_
    //     returns (uint tokenAmountIn, uint spotPriceAfter)
    // {
    //     require(_records[tokenIn].bound, "ERR_NOT_BOUND");
    //     require(_records[tokenOut].bound, "ERR_NOT_BOUND");
    //     require(_publicSwap, "ERR_SWAP_NOT_PUBLIC");

    //     Record storage inRecord = _records[address(tokenIn)];
    //     Record storage outRecord = _records[address(tokenOut)];

    //     require(tokenAmountOut <= bmul(outRecord.balance, MAX_OUT_RATIO), "ERR_MAX_OUT_RATIO");

    //     uint spotPriceBefore = calcSpotPrice(
    //                                 inRecord.balance,
    //                                 inRecord.denorm,
    //                                 outRecord.balance,
    //                                 outRecord.denorm,
    //                                 _swapFee
    //                             );
    //     require(spotPriceBefore <= maxPrice, "ERR_BAD_LIMIT_PRICE");

    //     tokenAmountIn = calcInGivenOut(
    //                         inRecord.balance,
    //                         inRecord.denorm,
    //                         outRecord.balance,
    //                         outRecord.denorm,
    //                         tokenAmountOut,
    //                         _swapFee
    //                     );
    //     require(tokenAmountIn <= maxAmountIn, "ERR_LIMIT_IN");

    //     inRecord.balance = badd(inRecord.balance, tokenAmountIn);
    //     outRecord.balance = bsub(outRecord.balance, tokenAmountOut);

    //     spotPriceAfter = calcSpotPrice(
    //                             inRecord.balance,
    //                             inRecord.denorm,
    //                             outRecord.balance,
    //                             outRecord.denorm,
    //                             _swapFee
    //                         );
    //     require(spotPriceAfter >= spotPriceBefore, "ERR_MATH_APPROX");
    //     require(spotPriceAfter <= maxPrice, "ERR_LIMIT_PRICE");
    //     require(spotPriceBefore <= bdiv(tokenAmountIn, tokenAmountOut), "ERR_MATH_APPROX");

    //     emit LOG_SWAP(msg.sender, tokenIn, tokenOut, tokenAmountIn, tokenAmountOut);

    //     _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);
    //     _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);

    //     return (tokenAmountIn, spotPriceAfter);
    // }
    



    function joinswapExternAmountIn(address tokenIn, uint tokenAmountIn, uint minPoolAmountOut)
        external
        _logs_
        _lock_
        returns (uint poolAmountOut)

    {
        require(_finalized, "ERR_NOT_FINALIZED");
        require(_records[tokenIn].bound, "ERR_NOT_BOUND");
        require(tokenAmountIn <= bmul(_records[tokenIn].balance, MAX_IN_RATIO), "ERR_MAX_IN_RATIO");

        Record storage inRecord = _records[tokenIn];

        // poolAmountOut = calcPoolOutGivenSingleIn(
        //                     inRecord.balance,
        //                     inRecord.denorm,
        //                     _totalSupply,
        //                     _totalWeight,
        //                     tokenAmountIn,
        //                     _swapFee
        //                 );
        poolAmountOut = tokenAmountIn;

        require(poolAmountOut >= minPoolAmountOut, "ERR_LIMIT_OUT");

        inRecord.balance = badd(inRecord.balance, tokenAmountIn);

        emit LOG_JOIN(msg.sender, tokenIn, tokenAmountIn);

        _mintPoolShare(poolAmountOut);
        _pushPoolShare(msg.sender, poolAmountOut);
        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);

        return poolAmountOut;
    }

    function joinswapPoolAmountOut(address tokenIn, uint poolAmountOut, uint maxAmountIn)
        external
        _logs_
        _lock_
        returns (uint tokenAmountIn)
    {
        require(_finalized, "ERR_NOT_FINALIZED");
        require(_records[tokenIn].bound, "ERR_NOT_BOUND");

        Record storage inRecord = _records[tokenIn];

        // tokenAmountIn = calcSingleInGivenPoolOut(
        //                     inRecord.balance,
        //                     inRecord.denorm,
        //                     _totalSupply,
        //                     _totalWeight,
        //                     poolAmountOut,
        //                     _swapFee
        //                 );
        tokenAmountIn = poolAmountOut;

        require(tokenAmountIn != 0, "ERR_MATH_APPROX");
        require(tokenAmountIn <= maxAmountIn, "ERR_LIMIT_IN");

        require(tokenAmountIn <= bmul(_records[tokenIn].balance, MAX_IN_RATIO), "ERR_MAX_IN_RATIO");

        inRecord.balance = badd(inRecord.balance, tokenAmountIn);

        emit LOG_JOIN(msg.sender, tokenIn, tokenAmountIn);

        _mintPoolShare(poolAmountOut);
        _pushPoolShare(msg.sender, poolAmountOut);
        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);

        return tokenAmountIn;
    }

    function exitswapPoolAmountIn(address tokenOut, uint poolAmountIn, uint minAmountOut)
        external
        _logs_
        _lock_
        returns (uint tokenAmountOut)
    {
        require(_finalized, "ERR_NOT_FINALIZED");
        require(_records[tokenOut].bound, "ERR_NOT_BOUND");

        Record storage outRecord = _records[tokenOut];

        // tokenAmountOut = calcSingleOutGivenPoolIn(
        //                     outRecord.balance,
        //                     outRecord.denorm,
        //                     _totalSupply,
        //                     _totalWeight,
        //                     poolAmountIn,
        //                     _swapFee
        //                 );
        tokenAmountOut = poolAmountIn;

        require(tokenAmountOut >= minAmountOut, "ERR_LIMIT_OUT");

        require(tokenAmountOut <= bmul(_records[tokenOut].balance, MAX_OUT_RATIO), "ERR_MAX_OUT_RATIO");

        outRecord.balance = bsub(outRecord.balance, tokenAmountOut);

        uint exitFee = bmul(poolAmountIn, EXIT_FEE);

        emit LOG_EXIT(msg.sender, tokenOut, tokenAmountOut);

        _pullPoolShare(msg.sender, poolAmountIn);
        _burnPoolShare(bsub(poolAmountIn, exitFee));
        _pushPoolShare(_factory, exitFee);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);

        return tokenAmountOut;
    }

    function exitswapExternAmountOut(address tokenOut, uint tokenAmountOut, uint maxPoolAmountIn)
        external
        _logs_
        _lock_
        returns (uint poolAmountIn)
    {
        require(_finalized, "ERR_NOT_FINALIZED");
        require(_records[tokenOut].bound, "ERR_NOT_BOUND");
        require(tokenAmountOut <= bmul(_records[tokenOut].balance, MAX_OUT_RATIO), "ERR_MAX_OUT_RATIO");

        Record storage outRecord = _records[tokenOut];

        // poolAmountIn = calcPoolInGivenSingleOut(
        //                     outRecord.balance,
        //                     outRecord.denorm,
        //                     _totalSupply,
        //                     _totalWeight,
        //                     tokenAmountOut,
        //                     _swapFee
        //                 );
        poolAmountIn = tokenAmountOut;

        require(poolAmountIn != 0, "ERR_MATH_APPROX");
        require(poolAmountIn <= maxPoolAmountIn, "ERR_LIMIT_IN");

        outRecord.balance = bsub(outRecord.balance, tokenAmountOut);

        uint exitFee = bmul(poolAmountIn, EXIT_FEE);

        emit LOG_EXIT(msg.sender, tokenOut, tokenAmountOut);

        _pullPoolShare(msg.sender, poolAmountIn);
        _burnPoolShare(bsub(poolAmountIn, exitFee));
        _pushPoolShare(_factory, exitFee);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);

        return poolAmountIn;
    }


    // ==
    // 'Underlying' token-manipulation functions make external calls but are NOT locked
    // You must `_lock_` or otherwise ensure reentry-safety

    function _pullUnderlying(address erc20, address from, uint amount)
        internal
    {
        bool xfer = IERC20(erc20).transferFrom(from, address(this), amount);
        require(xfer, "ERR_ERC20_FALSE");
    }

    function _pushUnderlying(address erc20, address to, uint amount)
        internal
    {
        bool xfer = IERC20(erc20).transfer(to, amount);
        require(xfer, "ERR_ERC20_FALSE");
    }

    function _pullPoolShare(address from, uint amount)
        internal
    {
        _pull(from, amount);
    }

    function _pushPoolShare(address to, uint amount)
        internal
    {
        _push(to, amount);
    }

    function _mintPoolShare(uint amount)
        internal
    {
        _mint(amount);
    }

    function _burnPoolShare(uint amount)
        internal
    {
        _burn(amount);
    }
    
// InitializableOwnable
    
    address public _OWNER_;
    address public _NEW_OWNER_;

    // ============ Events ============

    event OwnershipTransferPrepared(address indexed previousOwner, address indexed newOwner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

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
    
// Storage

    struct Record {
        bool bound;   // is token bound to pool
        uint index;   // private
        uint denorm;  // denormalized weight
        uint balance;
        Types.RStatus RStatus;
        uint targetTokenAmount;
        uint balanceLimit;
        address token;
    }

    // ============ Variables for Control ============

    // bool internal _INITIALIZED_;
    // bool public _CLOSED_;
    // bool public _DEPOSIT_QUOTE_ALLOWED_;
    // bool public _DEPOSIT_BASE_ALLOWED_;
    // bool public _TRADE_ALLOWED_;
    // uint256 public _GAS_PRICE_LIMIT_; 

    // ============ Advanced Controls ============
    // bool public _BUYING_ALLOWED_;
    // bool public _SELLING_ALLOWED_;
    // uint256 public _BASE_BALANCE_LIMIT_;
    // uint256 public _QUOTE_BALANCE_LIMIT_;

    // ============ Core Address ============

    address public _SUPERVISOR_; // could freeze system in emergency
    address public _MAINTAINER_; // collect maintainer fee to buy food for DODO

    // address public _BASE_TOKEN_;
    // address public _QUOTE_TOKEN_;
    // address public _ORACLE_;
    
    mapping(address => mapping(address => uint256)) internal _oracles;

    // ============ Variables for PMM Algorithm ============

    uint256 public _LP_FEE_RATE_;
    uint256 public _MT_FEE_RATE_;
    uint256 public _K_;

    // Types.RStatus public _R_STATUS_;
    // uint256 public _TARGET_BASE_TOKEN_AMOUNT_;
    // uint256 public _TARGET_QUOTE_TOKEN_AMOUNT_;
    // uint256 public _BASE_BALANCE_;
    // uint256 public _QUOTE_BALANCE_;

    // address public _BASE_CAPITAL_TOKEN_;
    // address public _QUOTE_CAPITAL_TOKEN_;

    // ============ Variables for Final Settlement ============

    // uint256 public _BASE_CAPITAL_RECEIVE_QUOTE_;
    // uint256 public _QUOTE_CAPITAL_RECEIVE_BASE_;
    // mapping(address => bool) public _CLAIMED_;

    // ============ Modifiers ============

    modifier onlySupervisorOrOwner() {
        require(msg.sender == _SUPERVISOR_ || msg.sender == _OWNER_, "NOT_SUPERVISOR_OR_OWNER");
        _;
    }

    // modifier notClosed() {
    //     require(!_CLOSED_, "DODO_CLOSED");
    //     _;
    // }

    // ============ Helper Functions ============

    function _checkDODOParameters() internal view returns (uint256) {
        require(_K_ < DecimalMath.ONE, "K>=1");
        require(_K_ > 0, "K=0");
        require(_LP_FEE_RATE_.add(_MT_FEE_RATE_) < DecimalMath.ONE, "FEE_RATE>=1");
    }

    function getOraclePrice(address base, address quote) public view returns (uint256) {
        // return IOracle(_ORACLE_).getPrice();
        // return 5 * (10**3);
        return _oracles[base][quote];
    }

    function getBaseCapitalBalanceOf(address base, address lp) public view returns (uint256) {
        return IDODOLpToken(base).balanceOf(lp);
    }

    function getTotalBaseCapital(address base) public view returns (uint256) {
        return IDODOLpToken(base).totalSupply();
    }

    function getQuoteCapitalBalanceOf(address quote, address lp) public view returns (uint256) {
        return IDODOLpToken(quote).balanceOf(lp);
    }

    function getTotalQuoteCapital(address quote) public view returns (uint256) {
        return IDODOLpToken(quote).totalSupply();
    }

    // ============ Version Control ============
    function version() external pure returns (uint256) {
        return 101; // 1.0.1
    }
    
// Pricing

    // ============ R = 1 cases ============

    function _ROneSellBaseToken(address base, address quote, uint256 amount, uint256 targetQuoteTokenAmount)
        internal
        view
        returns (uint256 receiveQuoteToken)
    {
        uint256 i = getOraclePrice(base, quote);

        uint256 Q2 = DODOMath._SolveQuadraticFunctionForTrade(
            targetQuoteTokenAmount,
            targetQuoteTokenAmount,
            DecimalMath.mul(i, amount),
            false,
            _K_
        );
        // in theory Q2 <= targetQuoteTokenAmount
        // however when amount is close to 0, precision problems may cause Q2 > targetQuoteTokenAmount
        return targetQuoteTokenAmount.sub(Q2);
    }

    function _ROneBuyBaseToken(address base, address quote, uint256 amount, uint256 targetBaseTokenAmount)
        internal
        view
        returns (uint256 payQuoteToken)
    {
        require(amount < targetBaseTokenAmount, "DODO_BASE_BALANCE_NOT_ENOUGH");
        uint256 B2 = targetBaseTokenAmount.sub(amount);
        payQuoteToken = _RAboveIntegrate(base, quote, targetBaseTokenAmount, targetBaseTokenAmount, B2);
        return payQuoteToken;
    }

    // ============ R < 1 cases ============

    function _RBelowSellBaseToken(
        address base,
        address quote,
        uint256 amount,
        uint256 quoteBalance,
        uint256 targetQuoteAmount
    ) internal view returns (uint256 receieQuoteToken) {
        uint256 i = getOraclePrice(base, quote);
        uint256 Q2 = DODOMath._SolveQuadraticFunctionForTrade(
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
    ) internal view returns (uint256 payQuoteToken) {
        // Here we don't require amount less than some value
        // Because it is limited at upper function
        // See Trader.queryBuyBaseToken
        uint256 i = getOraclePrice(base, quote);
        uint256 Q2 = DODOMath._SolveQuadraticFunctionForTrade(
            targetQuoteAmount,
            quoteBalance,
            DecimalMath.mulCeil(i, amount),
            true,
            _K_
        );
        return Q2.sub(quoteBalance);
    }

    function _RBelowBackToOne(Record memory baseToken, Record memory quoteToken) internal view returns (uint256 payQuoteToken) {
        // important: carefully design the system to make sure spareBase always greater than or equal to 0
        uint256 spareBase = baseToken.balance.sub(baseToken.targetTokenAmount);
        uint256 price = getOraclePrice(baseToken.token, quoteToken.token);
        uint256 fairAmount = DecimalMath.mul(spareBase, price);
        uint256 newTargetQuote = DODOMath._SolveQuadraticFunctionForTarget(
            baseToken.balance,
            _K_,
            fairAmount
        );
        return newTargetQuote.sub(quoteToken.balance);
    }

    // ============ R > 1 cases ============

    function _RAboveBuyBaseToken(
        address base,
        address quote,
        uint256 amount,
        uint256 baseBalance,
        uint256 targetBaseAmount
    ) internal view returns (uint256 payQuoteToken) {
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
    ) internal view returns (uint256 receiveQuoteToken) {
        // here we don't require B1 <= targetBaseAmount
        // Because it is limited at upper function
        // See Trader.querySellBaseToken
        uint256 B1 = baseBalance.add(amount);
        return _RAboveIntegrate(base, quote, targetBaseAmount, B1, baseBalance);
    }

    function _RAboveBackToOne(Record memory baseToken, Record memory quoteToken) internal view returns (uint256 payBaseToken) {
        // important: carefully design the system to make sure spareBase always greater than or equal to 0
        uint256 spareQuote = quoteToken.balance.sub(quoteToken.targetTokenAmount);
        uint256 price = getOraclePrice(baseToken.token, quoteToken.token);
        uint256 fairAmount = DecimalMath.divFloor(spareQuote, price);
        uint256 newTargetBase = DODOMath._SolveQuadraticFunctionForTarget(
            baseToken.balance,
            _K_,
            fairAmount
        );
        return newTargetBase.sub(baseToken.balance);
    }

    // ============ Helper functions ============

    function getExpectedTarget(address base, address quote) public view returns (uint256 baseTarget, uint256 quoteTarget) {
        Record memory baseToken = _records[base];
        Record memory quoteToken = _records[quote];
        uint256 Q = quoteToken.balance;
        uint256 B = baseToken.balance;
        if (baseToken.RStatus == Types.RStatus.ONE) {
            return (baseToken.targetTokenAmount, quoteToken.targetTokenAmount);
        } else if (baseToken.RStatus == Types.RStatus.BELOW_ONE) {
            uint256 payQuoteToken = _RBelowBackToOne(baseToken, quoteToken);
            return (baseToken.targetTokenAmount, Q.add(payQuoteToken));
        } else if (baseToken.RStatus == Types.RStatus.ABOVE_ONE) {
            uint256 payBaseToken = _RAboveBackToOne(baseToken, quoteToken);
            return (B.add(payBaseToken), quoteToken.targetTokenAmount);
        }
    }

    // function getMidPrice() public view returns (uint256 midPrice) {
    //     (uint256 baseTarget, uint256 quoteTarget) = getExpectedTarget();
    //     if (_R_STATUS_ == Types.RStatus.BELOW_ONE) {
    //         uint256 R = DecimalMath.divFloor(
    //             quoteTarget.mul(quoteTarget).div(_QUOTE_BALANCE_),
    //             _QUOTE_BALANCE_
    //         );
    //         R = DecimalMath.ONE.sub(_K_).add(DecimalMath.mul(_K_, R));
    //         return DecimalMath.divFloor(getOraclePrice(), R);
    //     } else {
    //         uint256 R = DecimalMath.divFloor(
    //             baseTarget.mul(baseTarget).div(_BASE_BALANCE_),
    //             _BASE_BALANCE_
    //         );
    //         R = DecimalMath.ONE.sub(_K_).add(DecimalMath.mul(_K_, R));
    //         return DecimalMath.mul(getOraclePrice(), R);
    //     }
    // }

    function _RAboveIntegrate(
        address base,
        address quote,
        uint256 B0,
        uint256 B1,
        uint256 B2
    ) internal view returns (uint256) {
        uint256 i = getOraclePrice(base, quote);
        return DODOMath._GeneralIntegrate(B0, B1, B2, i, _K_);
    }

    // function _RBelowIntegrate(
    //     uint256 Q0,
    //     uint256 Q1,
    //     uint256 Q2
    // ) internal view returns (uint256) {
    //     uint256 i = getOraclePrice();
    //     i = DecimalMath.divFloor(DecimalMath.ONE, i); // 1/i
    //     return DODOMath._GeneralIntegrate(Q0, Q1, Q2, i, _K_);
    // }
    
    // Settlement
    using SafeMath for uint256;
    // using SafeERC20 for IERC20;
    
    // struct Record {
    //     bool bound;   // is token bound to pool
    //     uint index;   // private
    //     uint denorm;  // denormalized weight
    //     uint balance;
    //     Types.RStatus RStatus;
    //     uint targetTokenAmount;
    //     uint balanceLimit;
    // }

    // ============ Events ============

    event Donate(uint256 amount, bool isBaseToken);

    event ClaimAssets(address indexed user, uint256 baseTokenAmount, uint256 quoteTokenAmount);

    // ============ Assets IN/OUT Functions ============

    function _baseTokenTransferIn(Record memory baseToken, address base, address from, uint256 amount) internal {
        require(baseToken.balance.add(amount) <= baseToken.balanceLimit, "BASE_BALANCE_LIMIT_EXCEEDED");
        IERC20(base).transferFrom(from, address(this), amount);
        baseToken.balance = baseToken.balance.add(amount);
    }

    function _quoteTokenTransferIn(Record memory quoteToken, address quote, address from, uint256 amount) internal {
        require(
            quoteToken.balance.add(amount) <= quoteToken.balanceLimit,
            "QUOTE_BALANCE_LIMIT_EXCEEDED"
        );
        IERC20(quote).transferFrom(from, address(this), amount);
        quoteToken.balance = quoteToken.balance.add(amount);
    }

    function _baseTokenTransferOut(Record memory baseToken, address base, address to, uint256 amount) internal {
        IERC20(base).transfer(to, amount);
        baseToken.balance = baseToken.balance.sub(amount);
    }

    function _quoteTokenTransferOut(Record memory quoteToken, address quote, address to, uint256 amount) internal {
        IERC20(quote).transfer(to, amount);
        quoteToken.balance = quoteToken.balance.sub(amount);
    }

    // ============ Donate to Liquidity Pool Functions ============

    // function _donateBaseToken(uint256 amount) internal {
    //     _TARGET_BASE_TOKEN_AMOUNT_ = _TARGET_BASE_TOKEN_AMOUNT_.add(amount);
    //     emit Donate(amount, true);
    // }

    // function _donateQuoteToken(uint256 amount) internal {
    //     _TARGET_QUOTE_TOKEN_AMOUNT_ = _TARGET_QUOTE_TOKEN_AMOUNT_.add(amount);
    //     emit Donate(amount, false);
    // }

    // function donateBaseToken(uint256 amount) external preventReentrant {
    //     _baseTokenTransferIn(msg.sender, amount);
    //     _donateBaseToken(amount);
    // }

    // function donateQuoteToken(uint256 amount) external preventReentrant {
    //     _quoteTokenTransferIn(msg.sender, amount);
    //     _donateQuoteToken(amount);
    // }

    // ============ Final Settlement Functions ============

    // last step to shut down dodo
    // function finalSettlement(Record memory baseToken, Record memory quoteToken, address base, address quote) external onlyOwner notClosed {
    //     _CLOSED_ = true;
    //     _DEPOSIT_QUOTE_ALLOWED_ = false;
    //     _DEPOSIT_BASE_ALLOWED_ = false;
    //     _TRADE_ALLOWED_ = false;
    //     uint256 totalBaseCapital = getTotalBaseCapital(base);
    //     uint256 totalQuoteCapital = getTotalQuoteCapital(quote);

    //     if (quoteToken.balance > quoteToken.targetTokenAmount) {
    //         uint256 spareQuote = quoteToken.balance.sub(quoteToken.targetTokenAmount);
    //         _BASE_CAPITAL_RECEIVE_QUOTE_ = DecimalMath.divFloor(spareQuote, totalBaseCapital);
    //     } else {
    //         quoteToken.targetTokenAmount = quoteToken.balance;
    //     }

    //     if (baseToken.balance > baseToken.targetTokenAmount) {
    //         uint256 spareBase = baseToken.balance.sub(baseToken.targetTokenAmount);
    //         _QUOTE_CAPITAL_RECEIVE_BASE_ = DecimalMath.divFloor(spareBase, totalQuoteCapital);
    //     } else {
    //         baseToken.targetTokenAmount = baseToken.balance;
    //     }

    //     baseToken.RStatus = Types.RStatus.ONE;
    // }

 //   claim remaining assets after final settlement
    // function claimAssets(Record memory baseToken, Record memory quoteToken, address base, address quote) external preventReentrant {
    //     require(_CLOSED_, "DODO_NOT_CLOSED");
    //     require(!_CLAIMED_[msg.sender], "ALREADY_CLAIMED");
    //     _CLAIMED_[msg.sender] = true;

    //     uint256 quoteCapital = getQuoteCapitalBalanceOf(base, msg.sender);
    //     uint256 baseCapital = getBaseCapitalBalanceOf(quote, msg.sender);

    //     uint256 quoteAmount = 0;
    //     if (quoteCapital > 0) {
    //         quoteAmount = quoteToken.targetTokenAmount.mul(quoteCapital).div(getTotalQuoteCapital(quote));
    //     }
    //     uint256 baseAmount = 0;
    //     if (baseCapital > 0) {
    //         baseAmount = baseToken.targetTokenAmount.mul(baseCapital).div(getTotalBaseCapital(base));
    //     }

    //     quoteToken.targetTokenAmount = quoteToken.targetTokenAmount.sub(quoteAmount);
    //     baseToken.targetTokenAmount = baseToken.targetTokenAmount.sub(baseAmount);

    //     quoteAmount = quoteAmount.add(DecimalMath.mul(baseCapital, _BASE_CAPITAL_RECEIVE_QUOTE_));
    //     baseAmount = baseAmount.add(DecimalMath.mul(quoteCapital, _QUOTE_CAPITAL_RECEIVE_BASE_));

    //     _baseTokenTransferOut(baseToken, base, msg.sender, baseAmount);
    //     _quoteTokenTransferOut(baseToken, quote, msg.sender, quoteAmount);

    //     IDODOLpToken(base).burn(msg.sender, baseCapital);
    //     IDODOLpToken(quote).burn(msg.sender, quoteCapital);

    //     emit ClaimAssets(msg.sender, baseAmount, quoteAmount);
    //     return;
    // }

    // in case someone transfer to contract directly
    // function retrieve(address token, uint256 amount) external onlyOwner {
    //     if (token == _BASE_TOKEN_) {
    //         require(
    //             IERC20(_BASE_TOKEN_).balanceOf(address(this)) >= _BASE_BALANCE_.add(amount),
    //             "DODO_BASE_BALANCE_NOT_ENOUGH"
    //         );
    //     }
    //     if (token == _QUOTE_TOKEN_) {
    //         require(
    //             IERC20(_QUOTE_TOKEN_).balanceOf(address(this)) >= _QUOTE_BALANCE_.add(amount),
    //             "DODO_QUOTE_BALANCE_NOT_ENOUGH"
    //         );
    //     }
    //     IERC20(token).safeTransfer(msg.sender, amount);
    // }

// Trader

        // ============ Events ============

    event SellBaseToken(address indexed seller, uint256 payBase, uint256 receiveQuote);

    event BuyBaseToken(address indexed buyer, uint256 receiveBase, uint256 payQuote);

    event ChargeMaintainerFee(address indexed maintainer, bool isBaseToken, uint256 amount);

    // ============ Modifiers ============

    // modifier tradeAllowed() {
    //     require(_TRADE_ALLOWED_, "TRADE_NOT_ALLOWED");
    //     _;
    // }

    // modifier buyingAllowed() {
    //     require(_BUYING_ALLOWED_, "BUYING_NOT_ALLOWED");
    //     _;
    // }

    // modifier sellingAllowed() {
    //     require(_SELLING_ALLOWED_, "SELLING_NOT_ALLOWED");
    //     _;
    // }

    // modifier gasPriceLimit() {
    //     require(tx.gasprice <= _GAS_PRICE_LIMIT_, "GAS_PRICE_EXCEED");
    //     _;
    // }

    // ============ Trade Functions ============

    function sellBaseToken(
        address base,
        address quote,
        uint256 amount,
        uint256 minReceiveQuote
        // bytes calldata data
    // ) external tradeAllowed sellingAllowed gasPriceLimit preventReentrant returns (uint256) {
    ) external preventReentrant returns (uint256) {
        
        Record memory baseToken = _records[base]; 
        Record memory quoteToken = _records[quote]; 
        // query price
        (
            uint256 receiveQuote,
            // uint256 lpFeeQuote,
            // uint256 mtFeeQuote,
            Types.RStatus newRStatus,
            uint256 newQuoteTarget,
            uint256 newBaseTarget
        ) = _querySellBaseToken(baseToken, quoteToken, amount);
        require(receiveQuote >= minReceiveQuote, "SELL_BASE_RECEIVE_NOT_ENOUGH");

        // settle assets
        _quoteTokenTransferOut(quoteToken, quote, msg.sender, receiveQuote);
        // if (data.length > 0) {
        //     IDODOCallee(msg.sender).dodoCall(false, amount, receiveQuote, data);
        // }
        _baseTokenTransferIn(baseToken, base, msg.sender, amount);
        // if (mtFeeQuote != 0) {
        //     _quoteTokenTransferOut(_MAINTAINER_, mtFeeQuote);
        //     emit ChargeMaintainerFee(_MAINTAINER_, false, mtFeeQuote);
        // }

        // update TARGET
        if (quoteToken.targetTokenAmount != newQuoteTarget) {
            quoteToken.targetTokenAmount = newQuoteTarget;
        }
        if (baseToken.targetTokenAmount != newBaseTarget) {
            baseToken.targetTokenAmount = newBaseTarget;
        }
        if (baseToken.RStatus != newRStatus) {
            baseToken.RStatus = newRStatus;
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
        // bytes calldata data
    // ) external tradeAllowed buyingAllowed gasPriceLimit preventReentrant returns (uint256) {
    ) external preventReentrant returns (uint256) {
        
        Record memory baseToken = _records[base]; 
        Record memory quoteToken = _records[quote]; 
        
        // query price
        (
            uint256 payQuote,
            // uint256 lpFeeBase,
            // uint256 mtFeeBase,
            Types.RStatus newRStatus,
            uint256 newQuoteTarget,
            uint256 newBaseTarget
        ) = _queryBuyBaseToken(baseToken, quoteToken, amount);
        require(payQuote <= maxPayQuote, "BUY_BASE_COST_TOO_MUCH");

        // settle assets
        _baseTokenTransferOut(baseToken, base, msg.sender, amount);
        // if (data.length > 0) {
        //     IDODOCallee(msg.sender).dodoCall(true, amount, payQuote, data);
        // }
        _quoteTokenTransferIn(quoteToken, quote, msg.sender, payQuote);
        // if (mtFeeBase != 0) {
        //     _baseTokenTransferOut(_MAINTAINER_, mtFeeBase);
        //     emit ChargeMaintainerFee(_MAINTAINER_, true, mtFeeBase);
        // }

        // update TARGET
        if (quoteToken.targetTokenAmount != newQuoteTarget) {
            quoteToken.targetTokenAmount = newQuoteTarget;
        }
        if (baseToken.targetTokenAmount != newBaseTarget) {
            baseToken.targetTokenAmount = newBaseTarget;
        }
        if (baseToken.RStatus != newRStatus) {
            baseToken.RStatus = newRStatus;
        }

        // _donateBaseToken(lpFeeBase);
        emit BuyBaseToken(msg.sender, amount, payQuote);

        return payQuote;
    }

   // ============ Query Functions ============

    function querySellBaseToken(address base, address quote, uint256 amount) external view returns (uint256 receiveQuote) {
        (receiveQuote, , , ) = _querySellBaseToken(_records[base], _records[quote], amount);
        return receiveQuote;
    }

    function queryBuyBaseToken(address base, address quote, uint256 amount) external view returns (uint256 payQuote) {
        (payQuote, , , ) = _queryBuyBaseToken(_records[base], _records[quote], amount);
        return payQuote;
    }

    function _querySellBaseToken(Record memory baseToken, Record memory quoteToken, uint256 amount)
        internal
        view
        returns (
            uint256 receiveQuote,
            // uint256 lpFeeQuote,
            // uint256 mtFeeQuote,
            Types.RStatus newRStatus,
            uint256 newQuoteTarget,
            uint256 newBaseTarget
        )
    {
        (newBaseTarget, newQuoteTarget) = getExpectedTarget(baseToken.token, quoteToken.token);

        uint256 sellBaseAmount = amount;

        if (baseToken.RStatus == Types.RStatus.ONE) {
            // case 1: R=1
            // R falls below one
            receiveQuote = _ROneSellBaseToken(baseToken.token, quoteToken.token, sellBaseAmount, newQuoteTarget);
            newRStatus = Types.RStatus.BELOW_ONE;
        } else if (baseToken.RStatus == Types.RStatus.ABOVE_ONE) {
            uint256 backToOnePayBase = newBaseTarget.sub(baseToken.balance);
            uint256 backToOneReceiveQuote = quoteToken.balance.sub(newQuoteTarget);
            // case 2: R>1
            // complex case, R status depends on trading amount
            if (sellBaseAmount < backToOnePayBase) {
                // case 2.1: R status do not change
                receiveQuote = _RAboveSellBaseToken(baseToken.token, quoteToken.token, sellBaseAmount, baseToken.balance, newBaseTarget);
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
                    _ROneSellBaseToken(baseToken.token, quoteToken.token, sellBaseAmount.sub(backToOnePayBase), newQuoteTarget)
                )
                    ;
                newRStatus = Types.RStatus.BELOW_ONE;
            }
        } else {
            // _R_STATUS_ == Types.RStatus.BELOW_ONE
            // case 3: R<1
            receiveQuote = _RBelowSellBaseToken(baseToken.token, quoteToken.token, sellBaseAmount, quoteToken.balance, newQuoteTarget);
            newRStatus = Types.RStatus.BELOW_ONE;
        }

        // count fees
        // lpFeeQuote = DecimalMath.mul(receiveQuote, _LP_FEE_RATE_);
        // mtFeeQuote = DecimalMath.mul(receiveQuote, _MT_FEE_RATE_);
        // receiveQuote = receiveQuote.sub(lpFeeQuote).sub(mtFeeQuote);
        receiveQuote = receiveQuote;

        // return (receiveQuote, lpFeeQuote, mtFeeQuote, newRStatus, newQuoteTarget, newBaseTarget);
        return (receiveQuote, newRStatus, newQuoteTarget, newBaseTarget);
    }

    function _queryBuyBaseToken(Record memory baseToken, Record memory quoteToken, uint256 amount)
        internal
        view
        returns (
            uint256 payQuote,
            // uint256 lpFeeBase,
            // uint256 mtFeeBase,
            Types.RStatus newRStatus,
            uint256 newQuoteTarget,
            uint256 newBaseTarget
        )
    {
        (newBaseTarget, newQuoteTarget) =  getExpectedTarget(baseToken.token, quoteToken.token);

        // charge fee from user receive amount
        // lpFeeBase = DecimalMath.mul(amount, 0.3);
        // mtFeeBase = DecimalMath.mul(amount, _MT_FEE_RATE_);
        // uint256 buyBaseAmount = amount.add(lpFeeBase).add(mtFeeBase);
        uint256 buyBaseAmount = amount;

        if (baseToken.RStatus == Types.RStatus.ONE) {
            // case 1: R=1
            payQuote = _ROneBuyBaseToken(baseToken.token, quoteToken.token, buyBaseAmount, newBaseTarget);
            newRStatus = Types.RStatus.ABOVE_ONE;
        } else if (baseToken.RStatus == Types.RStatus.ABOVE_ONE) {
            // case 2: R>1
            payQuote = _RAboveBuyBaseToken(baseToken.token, quoteToken.token, buyBaseAmount, baseToken.balance, newBaseTarget);
            newRStatus = Types.RStatus.ABOVE_ONE;
        } else if (baseToken.RStatus == Types.RStatus.BELOW_ONE) {
            uint256 backToOnePayQuote = newQuoteTarget.sub(quoteToken.balance);
            uint256 backToOneReceiveBase = baseToken.balance.sub(newBaseTarget);
            // case 3: R<1
            // complex case, R status may change
            if (buyBaseAmount < backToOneReceiveBase) {
                // case 3.1: R status do not change
                // no need to check payQuote because spare base token must be greater than zero
                payQuote = _RBelowBuyBaseToken(baseToken.token, quoteToken.token, buyBaseAmount, quoteToken.balance, newQuoteTarget);
                newRStatus = Types.RStatus.BELOW_ONE;
            } else if (buyBaseAmount == backToOneReceiveBase) {
                // case 3.2: R status changes to ONE
                payQuote = backToOnePayQuote;
                newRStatus = Types.RStatus.ONE;
            } else {
                // case 3.3: R status changes to ABOVE_ONE
                payQuote = backToOnePayQuote.add(
                    _ROneBuyBaseToken(baseToken.token, quoteToken.token, buyBaseAmount.sub(backToOneReceiveBase), newBaseTarget)
                );
                newRStatus = Types.RStatus.ABOVE_ONE;
            }
        }

        // return (payQuote, lpFeeBase, mtFeeBase, newRStatus, newQuoteTarget, newBaseTarget);
        return (payQuote, newRStatus, newQuoteTarget, newBaseTarget);
    }
}

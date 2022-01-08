// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "./IERC2612.sol";

/**
 * Implementation adapted from
 * https://github.com/albertocuestacanada/ERC20Permit/blob/master/contracts/ERC20Permit.sol.
 */
abstract contract ERC2612Upgradeable is ERC165Upgradeable, ERC20Upgradeable, EIP712Upgradeable, IERC2612 {
    using CountersUpgradeable for CountersUpgradeable.Counter;

    mapping(address => CountersUpgradeable.Counter) private _nonces;

    // solhint-disable-next-line var-name-mixedcase
    bytes32 private _PERMIT_TYPEHASH;
    // solhint-disable-next-line var-name-mixedcase
    bytes32 private _TRANSFER_TYPEHASH;

    function __ERC2612_init(string memory name_) internal initializer {
        __Context_init_unchained();
        __EIP712_init_unchained(name_, "1");
        __ERC2612_init_unchained();
    }

    function __ERC2612_init_unchained() internal initializer {
        _PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
        _TRANSFER_TYPEHASH = keccak256("Transfer(address owner,address to,uint256 value,uint256 nonce,uint256 deadline)");
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC2612).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC20Permit-nonces}.
     */
    function nonces(address owner) public view virtual override returns (uint256) {
        return _nonces[owner].current();
    }

    /**
     * @dev See {IERC20Permit-DOMAIN_SEPARATOR}.
     */
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view override returns (bytes32) {
        return _domainSeparatorV4();
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override {
        verifyPermit(_PERMIT_TYPEHASH, owner, spender, value, deadline, v, r, s);
        _approve(owner, spender, value);
    }

    function transferWithPermit(
        address owner,
        address to,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (bool) {
        verifyPermit(_TRANSFER_TYPEHASH, owner, to, value, deadline, v, r, s);
        _transfer(owner, to, value);
        return true;
    }

    function verifyPermit(
        bytes32 typehash,
        address owner,
        address to,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        require(block.timestamp <= deadline, "ERC20Permit: expired deadline");

        bytes32 structHash = keccak256(abi.encode(typehash, owner, to, value, _useNonce(owner), deadline));

        require(
            verifyEIP712(owner, structHash, v, r, s) || verifyPersonalSign(owner, structHash, v, r, s),
            'ERC20Permit: invalid signature'
        );
    }

    function verifyEIP712(
        address owner,
        bytes32 structHash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal view returns (bool) {
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = ECDSAUpgradeable.recover(hash, v, r, s);
        return (signer != address(0) && signer == owner);
    }

    function verifyPersonalSign(
        address owner,
        bytes32 hashStruct,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (bool) {
        bytes32 hash = ECDSAUpgradeable.toEthSignedMessageHash(hashStruct);
        address signer = ECDSAUpgradeable.recover(hash, v, r, s);
        return (signer != address(0) && signer == owner);
    }

    /**
     * @dev "Consume a nonce": return the current value and increment.
     */
    function _useNonce(address owner) internal virtual returns (uint256 current) {
        CountersUpgradeable.Counter storage nonce = _nonces[owner];
        current = nonce.current();
        nonce.increment();
    }
}

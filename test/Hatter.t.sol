// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Test, console2 } from "forge-std/Test.sol";
import { HatterBase, DelegationContractLike } from "../src/HatterBase.sol";
import { IHatter } from "../src/IHatter.sol";
// import { Deploy } from "../script/Hatter.s.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";
import { ECDSA } from "solady/utils/ECDSA.sol";

contract HatterTest is Test {
  IHatter public hatter;

  uint256 public fork;
  uint256 public BLOCK_NUMBER = 17_671_864;
  IHats public HATS = IHats(0x3bc1A0Ad72417f2d411118085256fC53CBdDd137);

  string public tophatImage = "maker.png";
  uint256 public tophat;
  uint256 public registrarHat;
  uint256 public facilitatorHat;
  uint256 public delegateHat;

  address public maker = makeAddr("maker");
  address public facilitator = makeAddr("facilitator");
  address public delegate;
  uint256 public delegateKey;

  string delegateName = "Test Delegate";
  string public ecosystemActorMessage;
  bytes public ecosystemActorSignature;
  address public delegationContract1;
  address public delegationContractDelegate1;
  address public delegateEOA1;
  uint256 public delegateEOA1Key;
  string public adRecognition1;
  bytes public adRecognitionSignature1;
  address public delegationContract2;
  address public delegationContractDelegate2;
  address public delegateEOA2;
  uint256 public delegateEOA2Key;
  string public adRecognition2;
  bytes public adRecognitionSignature2;

  uint256 public expectedDelegateHatId;

  bytes public someBytes = abi.encodePacked("these are some bytes");

  HatterHarness public harness;
  SignerMock public signerContract;

  error InvalidEcosystemActorSignature();
  error InvalidADRecognitionSignature();
  error InvalidDelegationContracts();
  error InvalidDelegateAddresses();
  error InvalidContractDelegate();
  // Hats Protocol errors
  error NotAdmin(address user, uint256 hatId);

  event Registered(
    address delegate,
    string delegateName,
    uint256 delegateHatId,
    string ecosystemActorMessage,
    address delegationContract1,
    address delegationContractDelegate1,
    string aDRecognition1,
    address delegationContract2,
    address delegationContractDelegate2,
    string aDRecognition2
  );

  function setUp() public virtual {
    // create and activate a fork, at BLOCK_NUMBER
    fork = vm.createSelectFork(vm.rpcUrl("mainnet"), BLOCK_NUMBER);

    // initiate a delegate and private key for signing
    (delegate, delegateKey) = makeAddrAndKey("delegate");
    (delegateEOA1, delegateEOA1Key) = makeAddrAndKey("delegateEOA1");
    (delegateEOA2, delegateEOA2Key) = makeAddrAndKey("delegateEOA2");

    // create a new maker hats tree, with a tophat, registrar hat, and facilitator hat
    vm.startPrank(maker);
    tophat = HATS.mintTopHat(maker, "makerDAO", tophatImage);
    registrarHat = HATS.createHat(tophat, "registrar hat", 1, maker, maker, true, "");
    facilitatorHat = HATS.createHat(registrarHat, "facilitator hat", 1, maker, maker, true, "");

    // mint the facilitator hat to the facilitator
    HATS.mintHat(facilitatorHat, facilitator);
    vm.stopPrank();

    // deploy hatter via the script; set first arg to true to log deployment addresses
    // Deploy.prepare(false, registrarHat, facilitatorHat, facilitator); //
    // Deploy.run();

    // deploy pre-compiled contract
    hatter =
      IHatter(deployCode("optimized-out/Hatter.sol/Hatter.json", abi.encode(registrarHat, facilitatorHat, facilitator)));

    // mint the registar hat to the hatter
    vm.prank(maker);
    HATS.mintHat(registrarHat, address(hatter));
  }

  function signMessage(string memory message, uint256 privateKey) public pure returns (bytes memory signature) {
    uint8 v;
    bytes32 r;
    bytes32 s;
    bytes32 messageHash = ECDSA.toEthSignedMessageHash(keccak256(abi.encodePacked(message)));
    (v, r, s) = vm.sign(privateKey, messageHash);
    signature = bytes.concat(r, s, bytes1(v));
  }
}

contract DeployTest is HatterTest {
  function test_constants() public {
    assertEq(address(hatter.HATS()), address(HATS));
    assertEq(hatter.REGISTRAR_HAT(), registrarHat);
    assertEq(hatter.FACILITATOR_HAT(), facilitatorHat);
    assertEq(hatter.FACILITATOR(), facilitator);
  }

  function test_hatterisAdminOfFacilitatorHat() public {
    assertTrue(HATS.isAdminOfHat(address(hatter), facilitatorHat));
  }
}

contract HatterHarness is HatterBase {
  constructor(uint256 registrarHat, uint256 facilitatorHat, address facilitator)
    HatterBase(registrarHat, facilitatorHat, facilitator)
  { }

  function isValidSignature(string calldata message, bytes calldata signature, address signer)
    public
    view
    returns (bool)
  {
    bool result = _isValidSignature(message, signature, signer);
    // console2.log("_isValidSignature() result:", result);
    return result;
  }

  function validateDelegationContractData(
    address delegationContract,
    address delegationContractDelegate,
    string calldata adRecognition,
    bytes calldata adRecognitionSig
  ) public view {
    _validateDelegationContractData(delegationContract, delegationContractDelegate, adRecognition, adRecognitionSig);
  }

  function createAndMintDelegateHat(string calldata _delegateName, address _delegate)
    public
    returns (uint256 delegateHatId)
  {
    return _createAndMintDelegateHat(_delegateName, _delegate);
  }
}

contract SignerMock {
  // bytes4(keccak256("isValidSignature(bytes32,bytes)")
  bytes4 internal constant ERC1271_MAGIC_VALUE = 0x1626ba7e;

  mapping(bytes32 => bytes) public signed;

  function sign(string calldata message, bytes calldata signature) public {
    bytes32 messageHash = ECDSA.toEthSignedMessageHash(keccak256(abi.encodePacked(message)));
    // console2.log("messageHash", messageHash);
    // console2.log("signature", signature);
    signed[messageHash] = signature;
  }

  function isValidSignature(bytes32 messageHash, bytes calldata signature) public view returns (bytes4) {
    if (keccak256(signed[messageHash]) == keccak256(signature)) {
      return ERC1271_MAGIC_VALUE;
    } else {
      return 0xffffffff;
    }
  }
}

contract InternalTest is HatterTest {
  function setUp() public virtual override {
    super.setUp();
    harness = new HatterHarness(registrarHat, facilitatorHat, facilitator);
  }
}

contract IsValidSignature is InternalTest {
  string message;
  bytes signature;

  function setUp() public virtual override {
    super.setUp();
    signerContract = new SignerMock();
  }

  function test_eoaSignature_happy() public {
    message = "hello world, I am an EOA";
    signature = signMessage(message, delegateKey);

    assertTrue(harness.isValidSignature(message, signature, delegate));
  }

  function test_bad_eoaSignature_false() public {
    message = "hello world, I am a bad EOA";
    signature = someBytes;

    assertFalse(harness.isValidSignature(message, signature, maker));
  }

  function test_contractSignature_happy() public {
    message = "hello world, I am a smart contract";
    signature = signMessage(message, delegateKey);

    vm.prank(delegate);
    signerContract.sign(message, signature);

    assertTrue(harness.isValidSignature(message, signature, address(signerContract)));
  }

  function test_bad_contractSignature_false() public {
    message = "hello world, I am a bad smart contract";
    signature = signMessage(message, delegateKey);

    vm.prank(delegate);
    signerContract.sign(message, abi.encodePacked("some other bytes"));

    assertFalse(harness.isValidSignature(message, signature, address(signerContract)));
  }

  function test_example() public {
    message = "this is a test, hopefully it works";
    // message = "0xddf9b268c7375f5371a481c8b6bf7979cabf2e9aa288fafa9595d5e5b1c14c32";
    signature = abi.encode(
      hex"b426af7ac0323841496e628c164372180d251191c61cfe89258d01a580146672580fab8819d6af51766a03011518cd3eb571ca1e622faf3d88252b4e23e8956d1c"
    );

    // 09ef8bd4abbe9c0d0033f5a7b2483a6959597d8acdd8d0defbaa1b6dafc3ef1e_5a2cbeb8e5ff1dbf9ea18b94496d52b868a80f700d93feedcfd8c3bb59a145_1c
    // signature = abi.encode(
    //   hex"a30166506918671c75e40dde3d2ee9e758efec216d8e720a14a67e5d26b0515d4a238ddc5dec7b8ea5d59de8acdc2b83f54cd2b6d4614ee5e2a4505cce882b661c"
    // );

    // console2.log("messageHash", vm.toString(keccak256(abi.encodePacked(message))));

    assertTrue(harness.isValidSignature(message, signature, 0x26521eDE6e1796c6faEE57cBc68a178E78d8e23e));
  }

  function test_example2() public {
    message = "this is the deployer wallet";
    signature = signMessage(message, vm.envUint("PRIVATE_KEY"));
    console2.log("signature", vm.toString(signature));

    // signature from etherscan:
    // 0xef70d965e7b1c683ee5b8c7675d90a34d1d0fd3bb32e952653c3add9c9a786584592b34fa6500230657a28013cee88507c8adf2cc40d4ce6a77bd1d9a25b165c1b

    assertTrue(harness.isValidSignature(message, signature, 0x2A069e21395DC7f89F780F8cf5383a0Ff598B672));
  }

  function test_ecrecover() public {
    message = "Spengrah Test Delegate; Aug 5, 23:00";
    signature = abi.encode(
      hex"09ef8bd4abbe9c0d0033f5a7b2483a6959597d8acdd8d0defbaa1b6dafc3ef1e5e5a2cbeb8e5ff1dbf9ea18b94496d52b868a80f700d93feedcfd8c3bb59a1451c"
    );
    bytes32 messageHash = ECDSA.toEthSignedMessageHash(keccak256(abi.encodePacked(message)));
    bytes32 r = bytes32(hex"09ef8bd4abbe9c0d0033f5a7b2483a6959597d8acdd8d0defbaa1b6dafc3ef1e");
    bytes32 s = bytes32(hex"5e5a2cbeb8e5ff1dbf9ea18b94496d52b868a80f700d93feedcfd8c3bb59a145");
    uint8 v = 0x1c;

    // console2.log("messageHash", vm.toString(messageHash));
    // console2.log("r", vm.toString(r));
    // console2.log("s", vm.toString(s));
    // console2.log("v", vm.toString(v));

    address signer = ecrecover(messageHash, v, r, s);
    console2.log("signer", signer);

    assertTrue(signer == 0x26521eDE6e1796c6faEE57cBc68a178E78d8e23e);
  }
}

contract DelegationContractMock is DelegationContractLike {
  address public delegate;

  constructor(address _delegate) {
    delegate = _delegate;
  }
}

contract ValidateDelegationContractData is InternalTest {
  function setUp() public virtual override {
    super.setUp();
  }
  // happy: valid sig and delegate is correct

  function test_delegationContractMock() public {
    DelegationContractLike mock = new DelegationContractMock(delegate);

    assertEq(mock.delegate(), delegate);
    assertFalse(mock.delegate() == facilitator);
  }

  function test_happy() public {
    adRecognition1 = "I am a delegate";
    adRecognitionSignature1 = signMessage(adRecognition1, delegateEOA1Key);
    delegationContractDelegate1 = delegateEOA1;
    delegationContract1 = address(new DelegationContractMock(delegationContractDelegate1));

    harness.validateDelegationContractData(
      delegationContract1, delegationContractDelegate1, adRecognition1, adRecognitionSignature1
    );
  }

  // invalid sig and valid delegate
  function test_revert_invalidSig() public {
    adRecognition1 = "I am a delegate";
    adRecognitionSignature1 = someBytes; // invalid sig
    delegationContractDelegate1 = delegateEOA1;
    delegationContract1 = address(new DelegationContractMock(delegationContractDelegate1));

    vm.expectRevert(InvalidADRecognitionSignature.selector);

    harness.validateDelegationContractData(
      delegationContract1, delegationContractDelegate1, adRecognition1, adRecognitionSignature1
    );
  }

  // valid sig and invalid delegate
  function test_revert_invalidDelegate() public {
    adRecognition1 = "I am a delegate";
    adRecognitionSignature1 = signMessage(adRecognition1, delegateEOA1Key);
    delegationContractDelegate1 = delegateEOA1;
    delegationContract1 = address(new DelegationContractMock(address(999))); // invalid delegate

    vm.expectRevert(InvalidContractDelegate.selector);

    harness.validateDelegationContractData(
      delegationContract1, delegationContractDelegate1, adRecognition1, adRecognitionSignature1
    );
  }
}

contract CreateAndMintDelegateHat is InternalTest {
  string details;
  uint32 maxSupply;
  address eligibility;
  address toggle;
  string imageURI;
  bool mutable_;
  bool active;

  function expectedDetails(string memory _delegateName) public pure returns (string memory) {
    return string(abi.encodePacked("Aligned Delegate: ", _delegateName));
  }

  function test_createAndMintSucceeds() public {
    // give the harness the registrar hat
    vm.prank(maker);
    HATS.transferHat(registrarHat, address(hatter), address(harness));

    delegateHat = harness.createAndMintDelegateHat(delegateName, delegate);

    (details, maxSupply,, eligibility, toggle, imageURI,, mutable_, active) = HATS.viewHat(delegateHat);

    assertTrue(HATS.isAdminOfHat(address(harness), delegateHat));
    assertTrue(HATS.isAdminOfHat(facilitator, delegateHat));
    assertEq(details, expectedDetails(delegateName));
    assertEq(eligibility, facilitator);
    assertEq(toggle, facilitator);
    assertTrue(mutable_);
    assertEq(imageURI, tophatImage);
    assertEq(maxSupply, 1);
    assertTrue(HATS.isWearerOfHat(delegate, delegateHat));
  }

  function test_revert_notRegistrarHatWearer() public {
    // harness is not registrar hat wearer
    assertFalse(HATS.isWearerOfHat(address(harness), registrarHat));

    expectedDelegateHatId = HATS.getNextId(facilitatorHat);

    vm.expectRevert(abi.encodeWithSelector(NotAdmin.selector, harness, expectedDelegateHatId));
    harness.createAndMintDelegateHat(delegateName, delegate);
  }
}

contract Register is HatterTest {
  function setUp() public virtual override {
    super.setUp();

    // generate valid inputs (each revert test will override 1 or more of these)
    delegationContract1 = address(new DelegationContractMock(delegateEOA1));
    delegationContractDelegate1 = delegateEOA1;
    adRecognition1 = "August 1st, 2023, 12:00pm UTC; Following Demo AVC; AD: Test Delegate";
    adRecognitionSignature1 = signMessage(adRecognition1, delegateEOA1Key);
    delegationContract2 = address(new DelegationContractMock(delegateEOA2));
    delegationContractDelegate2 = delegateEOA2;
    adRecognition2 = "August 1st, 2023, 12:00pm UTC; Following Example AVC; AD: Test Delegate";
    adRecognitionSignature2 = signMessage(adRecognition2, delegateEOA2Key);
    ecosystemActorMessage = string.concat(adRecognition1, adRecognition2);
    ecosystemActorSignature = signMessage(ecosystemActorMessage, delegateKey);
  }

  function test_EOA_happy() public {
    expectedDelegateHatId = HATS.getNextId(facilitatorHat);

    // expect emit Registred
    vm.expectEmit(true, true, true, true);

    emit Registered(
      delegate,
      delegateName,
      expectedDelegateHatId,
      ecosystemActorMessage,
      delegationContract1,
      delegationContractDelegate1,
      adRecognition1,
      delegationContract2,
      delegationContractDelegate2,
      adRecognition2
    );

    vm.prank(delegate);

    delegateHat = hatter.register(
      delegateName,
      ecosystemActorMessage,
      ecosystemActorSignature,
      delegationContract1,
      delegationContractDelegate1,
      adRecognition1,
      adRecognitionSignature1,
      delegationContract2,
      delegationContractDelegate2,
      adRecognition2,
      adRecognitionSignature2
    );

    assertTrue(HATS.isWearerOfHat(delegate, expectedDelegateHatId));
  }

  function test_gas_EOA_happy() public {
    vm.prank(delegate);

    delegateHat = hatter.register(
      delegateName,
      ecosystemActorMessage,
      ecosystemActorSignature,
      delegationContract1,
      delegationContractDelegate1,
      adRecognition1,
      adRecognitionSignature1,
      delegationContract2,
      delegationContractDelegate2,
      adRecognition2,
      adRecognitionSignature2
    );
  }

  function test_contractSigner_happy() public {
    // recreate delegation contracts, delegates, and signatures
    uint256 signerKey1 = uint256(keccak256(abi.encodePacked("signer1")));
    adRecognitionSignature1 = signMessage(adRecognition1, signerKey1);
    SignerMock mock1 = new SignerMock();
    mock1.sign(adRecognition1, adRecognitionSignature1);
    delegationContract1 = address(new DelegationContractMock(address(mock1)));

    assertEq(DelegationContractLike(delegationContract1).delegate(), address(mock1));

    uint256 signerKey2 = uint256(keccak256(abi.encodePacked("signer2")));
    adRecognitionSignature2 = signMessage(adRecognition2, signerKey2);
    SignerMock mock2 = new SignerMock();
    mock2.sign(adRecognition2, adRecognitionSignature2);
    delegationContract2 = address(new DelegationContractMock(address(mock2)));

    assertEq(DelegationContractLike(delegationContract2).delegate(), address(mock2));

    expectedDelegateHatId = HATS.getNextId(facilitatorHat);

    // expect emit Registred
    vm.expectEmit(true, true, true, true);

    emit Registered(
      delegate,
      delegateName,
      expectedDelegateHatId,
      ecosystemActorMessage,
      delegationContract1,
      address(mock1),
      adRecognition1,
      delegationContract2,
      address(mock2),
      adRecognition2
    );

    vm.prank(delegate);

    delegateHat = hatter.register(
      delegateName,
      ecosystemActorMessage,
      ecosystemActorSignature,
      delegationContract1,
      address(mock1),
      adRecognition1,
      adRecognitionSignature1,
      delegationContract2,
      address(mock2),
      adRecognition2,
      adRecognitionSignature2
    );

    assertTrue(HATS.isWearerOfHat(delegate, expectedDelegateHatId));
  }

  function test_revert_delegateOverlapsContractDelegate1() public {
    vm.expectRevert(InvalidDelegateAddresses.selector);

    vm.prank(delegate);

    delegateHat = hatter.register(
      delegateName,
      ecosystemActorMessage,
      ecosystemActorSignature,
      delegationContract1,
      delegate, // should cause revert
      adRecognition1,
      adRecognitionSignature1,
      delegationContract2,
      delegationContractDelegate2,
      adRecognition2,
      adRecognitionSignature2
    );
  }

  function test_revert_delegateOverlapsContractDelegate2() public {
    vm.expectRevert(InvalidDelegateAddresses.selector);

    vm.prank(delegate);

    delegateHat = hatter.register(
      delegateName,
      ecosystemActorMessage,
      ecosystemActorSignature,
      delegationContract1,
      delegationContractDelegate1,
      adRecognition1,
      adRecognitionSignature1,
      delegationContract2,
      delegate, // should cause revert
      adRecognition2,
      adRecognitionSignature2
    );
  }

  function test_revert_sameContractDelegate() public {
    vm.expectRevert(InvalidDelegateAddresses.selector);

    vm.prank(delegate);

    delegateHat = hatter.register(
      delegateName,
      ecosystemActorMessage,
      ecosystemActorSignature,
      delegationContract1,
      delegationContractDelegate1,
      adRecognition1,
      adRecognitionSignature1,
      delegationContract2,
      delegationContractDelegate1, // should cause revert
      adRecognition2,
      adRecognitionSignature2
    );
  }

  function test_revert_sameDelegationContract() public {
    vm.expectRevert(InvalidDelegationContracts.selector);

    vm.prank(delegate);

    delegateHat = hatter.register(
      delegateName,
      ecosystemActorMessage,
      ecosystemActorSignature,
      delegationContract1,
      delegationContractDelegate1,
      adRecognition1,
      adRecognitionSignature1,
      delegationContract1, // should cause revert
      delegationContractDelegate2,
      adRecognition2,
      adRecognitionSignature2
    );
  }

  function test_revert_invalidEcosystemActorSignature() public {
    ecosystemActorSignature = signMessage("invalid", delegateKey);

    vm.expectRevert(InvalidEcosystemActorSignature.selector);

    vm.prank(delegate);

    delegateHat = hatter.register(
      delegateName,
      ecosystemActorMessage,
      ecosystemActorSignature, // should cause revert
      delegationContract1,
      delegationContractDelegate1,
      adRecognition1,
      adRecognitionSignature1,
      delegationContract2,
      delegationContractDelegate2,
      adRecognition2,
      adRecognitionSignature2
    );
  }

  function test_revert_invalidADRecognitionSignature1() public {
    // wrong message signed by the correct key
    adRecognitionSignature1 = signMessage("invalid", delegateEOA1Key);

    vm.expectRevert(InvalidADRecognitionSignature.selector);

    vm.prank(delegate);

    delegateHat = hatter.register(
      delegateName,
      ecosystemActorMessage,
      ecosystemActorSignature,
      delegationContract1,
      delegationContractDelegate1,
      adRecognition1,
      adRecognitionSignature1, // should cause revert
      delegationContract2,
      delegationContractDelegate2,
      adRecognition2,
      adRecognitionSignature2
    );
  }

  function test_revert_invalidContractDelegate1() public {
    delegationContract1 = address(new DelegationContractMock(address(999)));

    vm.expectRevert(InvalidContractDelegate.selector);

    vm.prank(delegate);

    delegateHat = hatter.register(
      delegateName,
      ecosystemActorMessage,
      ecosystemActorSignature,
      delegationContract1,
      delegationContractDelegate1, // should cause revert
      adRecognition1,
      adRecognitionSignature1,
      delegationContract2,
      delegationContractDelegate2,
      adRecognition2,
      adRecognitionSignature2
    );
  }

  function test_revert_invalidADRecognitionSignature2() public {
    // wrong message signed by the correct key
    adRecognitionSignature2 = signMessage("invalid", delegateEOA2Key);

    vm.expectRevert(InvalidADRecognitionSignature.selector);

    vm.prank(delegate);

    delegateHat = hatter.register(
      delegateName,
      ecosystemActorMessage,
      ecosystemActorSignature,
      delegationContract1,
      delegationContractDelegate1,
      adRecognition1,
      adRecognitionSignature1,
      delegationContract2,
      delegationContractDelegate2,
      adRecognition2,
      adRecognitionSignature2 // should cause revert
    );
  }

  function test_revert_invalidContractDelegate2() public {
    delegationContract2 = address(new DelegationContractMock(address(999)));

    vm.expectRevert(InvalidContractDelegate.selector);

    vm.prank(delegate);

    delegateHat = hatter.register(
      delegateName,
      ecosystemActorMessage,
      ecosystemActorSignature,
      delegationContract1,
      delegationContractDelegate1,
      adRecognition1,
      adRecognitionSignature1,
      delegationContract2,
      delegationContractDelegate2, // should cause revert
      adRecognition2,
      adRecognitionSignature2
    );
  }

  function test_revert_notRegistrarHatWearer() public {
    vm.prank(maker);
    HATS.transferHat(registrarHat, address(hatter), address(0));

    expectedDelegateHatId = HATS.getNextId(facilitatorHat);
    vm.expectRevert(abi.encodeWithSelector(NotAdmin.selector, address(hatter), expectedDelegateHatId));

    vm.prank(delegate);

    delegateHat = hatter.register(
      delegateName,
      ecosystemActorMessage,
      ecosystemActorSignature,
      delegationContract1,
      delegationContractDelegate1,
      adRecognition1,
      adRecognitionSignature1,
      delegationContract2,
      delegationContractDelegate2,
      adRecognition2,
      adRecognitionSignature2
    );
  }
}

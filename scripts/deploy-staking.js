require('dotenv').config()
const hre = require('hardhat')

const sleep = (delay) => new Promise((resolve) => setTimeout(resolve, delay * 1000));

async function main() {
  const ethers = hre.ethers
  const upgrades = hre.upgrades;

  console.log('network:', await ethers.provider.getNetwork())

  const signer = (await ethers.getSigners())[0]
  console.log('signer:', await signer.getAddress())

  const feeAddress = process.env.FEE_ADDRESS;

  /**
   * Deploy SingleNFTStaking Template
   */
  const SingleNFTStaking = await ethers.getContractFactory('SingleNFTStaking', { signer: (await ethers.getSigners())[0] })

  const singleNFTStakingContract = await SingleNFTStaking.deploy();
  await singleNFTStakingContract.deployed();
  await sleep(30);
  console.log("SingleNFTStaking template deployed to: ", singleNFTStakingContract.address);

  // Verify SingleNFTStaking Template
  try {
    await hre.run('verify:verify', {
      address: singleNFTStakingContract.address,
      constructorArguments: []
    })
    console.log('SingleNFTStaking verified')
  } catch (error) {
    console.log('SingleNFTStaking verification failed : ', error)
  }


  /**
   * Deploy MultiNFTStaking Template
   */
  const MultiNFTStaking = await ethers.getContractFactory('MultiNFTStaking', { signer: (await ethers.getSigners())[0] })

  const multiNFTStakingContract = await MultiNFTStaking.deploy();
  await multiNFTStakingContract.deployed();
  await sleep(30);
  console.log("MultiNFTStaking template deployed to: ", multiNFTStakingContract.address);

  // Verify MultiNFTStaking Template
  try {
    await hre.run('verify:verify', {
      address: multiNFTStakingContract.address,
      constructorArguments: []
    })
    console.log('MultiNFTStaking verified')
  } catch (error) {
    console.log('MultiNFTStaking verification failed : ', error)
  }

  /**
  *  Deploy and Verify NFTStakingFactory
  */
  {
    const NFTStakingFactory = await ethers.getContractFactory('NFTStakingFactory', {
      signer: (await ethers.getSigners())[0]
    });
    const nftStakingFactoryContract = await upgrades.deployProxy(NFTStakingFactory, [feeAddress, singleNFTStakingContract.address, multiNFTStakingContract.address], { initializer: 'initialize' });
    await nftStakingFactoryContract.deployed()

    console.log('NFTStakingFactory proxy deployed: ', nftStakingFactoryContract.address)

    nftStakingFactoryImplementation = await upgrades.erc1967.getImplementationAddress(nftStakingFactoryContract.address);
    console.log('NFTStakingFactory Implementation address: ', nftStakingFactoryImplementation)

    await sleep(60);
    // Verify NFTStakingFactory
    try {
      await hre.run('verify:verify', {
        address: nftStakingFactoryImplementation,
        constructorArguments: []
      })
      console.log('NFTStakingFactory verified')
    } catch (error) {
      console.log('NFTStakingFactory verification failed : ', error)
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })

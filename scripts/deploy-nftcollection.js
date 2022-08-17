require('dotenv').config()
const hre = require('hardhat')

const sleep = (delay) => new Promise((resolve) => setTimeout(resolve, delay * 1000));

async function main() {
  const ethers = hre.ethers
  const upgrades = hre.upgrades;

  console.log('network:', await ethers.provider.getNetwork())

  const signer = (await ethers.getSigners())[0]
  console.log('signer:', await signer.getAddress())

  /**
   * Deploy SingleNFT Template
   */
  const SingleNFT = await ethers.getContractFactory('SingleNFT', { signer: (await ethers.getSigners())[0] })

  const singleNFTContract = await SingleNFT.deploy();
  await singleNFTContract.deployed();
  await sleep(60);
  console.log("SingleNFT template deployed to: ", singleNFTContract.address);

  // Verify SingleNFT Template
  try {
    await hre.run('verify:verify', {
      address: singleNFTContract.address,
      constructorArguments: []
    })
    console.log('SingleNFT verified')
  } catch (error) {
    console.log('SingleNFT verification failed : ', error)
  }

  /**
   * Deploy MultipleNFT Template
   */
  const MultipleNFT = await ethers.getContractFactory('MultipleNFT', { signer: (await ethers.getSigners())[0] })

  const multipleNFTContract = await MultipleNFT.deploy();
  await multipleNFTContract.deployed();
  await sleep(60);
  console.log("MultipleNFT template deployed to: ", multipleNFTContract.address);

  // Verify MultipleNFT Template
  try {
    await hre.run('verify:verify', {
      address: multipleNFTContract.address,
      constructorArguments: []
    })
    console.log('MultipleNFT verified')
  } catch (error) {
    console.log('MultipleNFT verification failed : ', error)
  }

  /**
  *  Deploy and Verify NFTFactory
  */
  {
    const NFTFactory = await ethers.getContractFactory('NFTFactory', {
      signer: (await ethers.getSigners())[0]
    });
    const nftFactoryContract = await upgrades.deployProxy(NFTFactory, [singleNFTContract.address,multipleNFTContract.address], { initializer: 'initialize' });
    await nftFactoryContract.deployed()

    console.log('NFTFactory proxy deployed: ', nftFactoryContract.address)

    nftFactoryImplementation = await upgrades.erc1967.getImplementationAddress(nftFactoryContract.address);
    console.log('NFTFactory Implementation address: ', nftFactoryImplementation)

    await sleep(60);
    // Verify NFTFactory
    try {
      await hre.run('verify:verify', {
        address: nftFactoryImplementation,
        constructorArguments: []
      })
      console.log('NFTFactory verified')
    } catch (error) {
      console.log('NFTFactory verification failed : ', error)
    }
  }

}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })

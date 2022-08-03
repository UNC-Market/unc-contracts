require('dotenv').config()
const hre = require('hardhat')

async function main() {
  const ethers = hre.ethers;  

  console.log('network:', await ethers.provider.getNetwork())

  const signer = (await ethers.getSigners())[0]
  console.log('signer:', await signer.getAddress())

  const subscriptions = [
    {
      name: 'Basic',
      period: 2592000, // 1 months
      price: '1'
    },
    {
      name: 'Standard',
      period: 7776000, // 3 months
      price: '3'
    },
    {
      name: 'Premium',
      period: 15552000, // 6 months
      price: '5'
    }
  ];
  const aprs = [
    80, // 8 %
    120, // 12 %
    180, // 18 %
  ];

  /**
  * Initialize SingleNFTStakingFactory
  */
  {
    console.log('Initialize SingleNFTStakingFactory...')
    const singleFactoryAddress = '0x2a7e9cd0e3c3a8305ac020d04cb39c46b66ff39a';
    const SingleNFTStakingFactory = await ethers.getContractFactory('SingleNFTStakingFactory', {
      signer: (await ethers.getSigners())[0]
    });
    const singleNFTStakingFactory = SingleNFTStakingFactory.attach(singleFactoryAddress);
    // Add Subscriptions    
    for (let index = 0; index < subscriptions.length; index++) {
      const subscription = subscriptions[index];
      const tx = await singleNFTStakingFactory.addSubscription(subscription.name, subscription.period, ethers.utils.parseEther(subscription.price));
      await tx.wait();
      console.log('Add subscription : ', JSON.stringify(subscription));
    }

    // Add APR      
    for (let index = 0; index < aprs.length; index++) {
      const apr = aprs[index];
      const tx = await singleNFTStakingFactory.addApr(apr);
      await tx.wait();
      console.log('Add apr : ', apr);
    }
  }

  /**
  * Initialize MultiNFTStakingFactory
  */
  {
    console.log('Initialize MultiNFTStakingFactory...')
    const multiFactoryAddress = '0x83002f8e0ecd8900ce1eeb20460bdc8a13cd1671';
    const MultiNFTStakingFactory = await ethers.getContractFactory('MultiNFTStakingFactory', {
      signer: (await ethers.getSigners())[0]
    });
    const multiNFTStakingFactory = MultiNFTStakingFactory.attach(multiFactoryAddress);
  
    // Add Subscriptions    
    for (let index = 0; index < subscriptions.length; index++) {
      const subscription = subscriptions[index];
      const tx = await multiNFTStakingFactory.addSubscription(subscription.name, subscription.period, ethers.utils.parseEther(subscription.price));
      await tx.wait();
      console.log('Add subscription : ', JSON.stringify(subscription));
    }
  
    // Add APR      
    for (let index = 0; index < aprs.length; index++) {
      const apr = aprs[index];
      const tx = await multiNFTStakingFactory.addApr(apr);
      await tx.wait();
      console.log('Add apr : ', apr);
    }
  }

}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })

# silvia-pid
A software based PID for Rancilio Silvia espresso machines.

Created using a V6 E edition Silvia as the guinea pig, results may vary with other models but please log your successes/failures here in "issues".

This PID allows more accurate control of the brew temperatures of the Silvia and provides a more stable temperature (goodbye surfing).

Be aware that this uses a 64 bit version of a MongoDB database. This means stock Raspbian has no power here, I would opt for the latest 64bit ubuntu server distribution. Use the Raspberry PI Imager software to install with ease.

Once raspi is connected you will need to use apt to install Node, npm and npm to install "forever". If you want to host your web thing on a real website address rather than an IP on your network, I'll leave that up to you to figure out, but you can visit mine on coffee.srjwebster.com.

Please don't turn on my steamer while I'm brewing, or I'll have to build an authentication layer, which will be most uncool.

Technical interest? Why yes I did decide to quit ajax on the front end for polling temperatures from the api endpoint and subscribe the page to a stream of data via websockets. Mainly because I wanted to test that out, but also I put this on reddit and my poor pi was struggling with all the uncachable ajax requests. Web sockets could probably support several thousand concurrent users all getting the data absolutely live, which felt like a better solution.

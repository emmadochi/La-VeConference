const https = require('https');
https.get('https://cdn.jsdelivr.net/npm/livekit-client/dist/livekit-client.umd.min.js', (res) => {
    let body = '';
    res.on('data', d => body += d);
    res.on('end', () => {
        console.log(body.substring(0, 500));
    });
});

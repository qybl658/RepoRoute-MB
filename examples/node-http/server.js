const http = require('node:http');
const server = http.createServer((request, response) => {
  response.writeHead(200, {'Content-Type': 'text/plain'});
  response.end('RepoWayfinder MB health fixture\n');
});
server.listen(18765, '127.0.0.1', () => console.log('http://127.0.0.1:18765'));

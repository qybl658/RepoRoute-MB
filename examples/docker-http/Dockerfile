FROM node:22-alpine
EXPOSE 18766
CMD ["node", "-e", "require('http').createServer((q,s)=>s.end('RepoWayfinder container healthy')).listen(18766,'0.0.0.0')"]

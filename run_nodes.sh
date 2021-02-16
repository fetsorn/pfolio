#!/usr/bin/env bash
set -euo pipefail

mkdir -p logs

echo "node8";
npx hardhat node > logs/node8log.log 2> logs/node8err.log &
echo "node9";
npx hardhat node --port 9545 > logs/node9log.log 2> logs/node9err.log &
echo "go to sleep";
sleep 10;
echo "start deploy";
echo "node8";
npx hardhat run --network localhost scripts/deploy.js > logs/deploy8log.log 2> logs/deploy8err.log;
echo "node9";
npx hardhat run --network localhost9 scripts/deploy.js > logs/deploy9log.log 2> logs/deploy9err.log;
echo "finished";

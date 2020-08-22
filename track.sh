#!/usr/bin/env bash

set -e

if ! $(type jq > /dev/null 2>&1); then
  echo "'jq' executable not found"
  exit 1
fi

if ! $(type awk > /dev/null 2>&1); then
  echo "'awk' executable not found"
  exit 1
fi

FILENAME="$1"
if [ -z "$FILENAME" ]; then
  echo "Usage: ./stock.sh config.json"
  exit
fi

API_ENDPOINT="https://query1.finance.yahoo.com/v7/finance/quote?lang=en-US&region=US&corsDomain=finance.yahoo.com"

FIELDS=(
symbol
marketState
regularMarketPrice
regularMarketChange
regularMarketChangePercent
preMarketPrice
preMarketChange
preMarketChangePercent
postMarketPrice
postMarketChange
postMarketChangePercent
)

if [ -z "$NO_COLOR" ]; then
  : "${COLOR_BOLD:=\e[1;37m}"
  : "${COLOR_GREEN:=\e[32m}"
  : "${COLOR_RED:=\e[31m}"
  : "${COLOR_RESET:=\e[00m}"
fi

symbols=$(cat $FILENAME | jq -r '.purchased[].symbol' | paste -sd, -)
fields=$(IFS=,; echo "${FIELDS[*]}")

results=$(curl -s "$API_ENDPOINT&fields=$fields&symbols=$symbols" | jq '.quoteResponse .result')

query () {
  echo $results | jq -r ".[] | select(.symbol == \"$1\") | .$2"
}

config () {
  cat $FILENAME | jq -r ".purchased[] | select(.symbol == \"$1\") | .$2"
}

sum=0.0
for symbol in $(echo $symbols | sed "s/,/ /g"); do
  marketState="$(query $symbol 'marketState')"

  if [ -z $marketState ]; then
    printf 'No results for symbol "%s"\n' $symbol
    continue
  fi

  preMarketChange="$(query $symbol 'preMarketChange')"
  postMarketChange="$(query $symbol 'postMarketChange')"

  if [ $marketState == "PRE" ] \
    && [ $preMarketChange != "0" ] \
    && [ $preMarketChange != "null" ]; then
    nonRegularMarketSign='*'
    price=$(query $symbol 'preMarketPrice')
  elif [ $marketState != "REGULAR" ] \
    && [ $postMarketChange != "0" ] \
    && [ $postMarketChange != "null" ]; then
    nonRegularMarketSign='*'
    price=$(query $symbol 'postMarketPrice')
  else
    nonRegularMarketSign=''
    price=$(query $symbol 'regularMarketPrice')
  fi

  bought_at=$( config $symbol 'at')
  shares=$( config $symbol 'shares')
  profit_per_share=$(awk "BEGIN {print $price - $bought_at}") # profit per share
  diff=$(awk "BEGIN {print $profit_per_share * $shares}")
  sum=$(awk "BEGIN {print $sum + $diff}")

  if [ "$diff" == "0" ]; then
    color=
  elif ( echo "$diff" | grep -q ^- ); then
    color=$COLOR_RED
  else
    color=$COLOR_GREEN
  fi

  if [ "$price" != "null" ]; then
    printf "%-6s%-6d @ $%-8.4f$COLOR_BOLD\t%-8.4f$COLOR_RESET" $symbol $shares $bought_at $price
    printf "\t%-8s" "$nonRegularMarketSign"
    printf "$color%-8.2f" $profit_per_share 
    printf "$color%-8.2f$COLOR_RESET\n" $diff
  fi
done

printf '=========================================================================\n'
printf "NET PROFIT (US$): %55.2f\n" $sum


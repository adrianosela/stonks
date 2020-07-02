#!/usr/bin/env bash
set -e

LANG=C
LC_NUMERIC=C

FILENAME="$1"

if ! $(type jq > /dev/null 2>&1); then
  echo "'jq' is not in the PATH. (See: https://stedolan.github.io/jq/)"
  exit 1
fi

if [ -z "$FILENAME" ]; then
  echo "Usage: ./ticker.sh config.json"
  exit
fi

FIELDS=(symbol marketState regularMarketPrice regularMarketChange regularMarketChangePercent \
  preMarketPrice preMarketChange preMarketChangePercent postMarketPrice postMarketChange postMarketChangePercent)
API_ENDPOINT="https://query1.finance.yahoo.com/v7/finance/quote?lang=en-US&region=US&corsDomain=finance.yahoo.com"
CONFIG_FILENAME="./config.json"

if [ -z "$NO_COLOR" ]; then
  : "${COLOR_BOLD:=\e[1;37m}"
  : "${COLOR_GREEN:=\e[32m}"
  : "${COLOR_RED:=\e[31m}"
  : "${COLOR_RESET:=\e[00m}"
fi

symbols=$(cat $FILENAME | jq -r '.purchased[].symbol' | paste -sd, -)
fields=$(IFS=,; echo "${FIELDS[*]}")

results=$(curl --silent "$API_ENDPOINT&fields=$fields&symbols=$symbols" \
  | jq '.quoteResponse .result')

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
    diff=$preMarketChange
    percent=$(query $symbol 'preMarketChangePercent')
  elif [ $marketState != "REGULAR" ] \
    && [ $postMarketChange != "0" ] \
    && [ $postMarketChange != "null" ]; then
    nonRegularMarketSign='*'
    price=$(query $symbol 'postMarketPrice')
    diff=$postMarketChange
    percent=$(query $symbol 'postMarketChangePercent')
  else
    nonRegularMarketSign=''
    price=$(query $symbol 'regularMarketPrice')
    diff=$(query $symbol 'regularMarketChange')
    percent=$(query $symbol 'regularMarketChangePercent')
  fi

  if [ "$diff" == "0" ]; then
    color=
  elif ( echo "$diff" | grep -q ^- ); then
    color=$COLOR_RED
  else
    color=$COLOR_GREEN
  fi

  bought_at=$( config $symbol 'at')
  shares=$( config $symbol 'shares')
  profit_per_share=$(awk "BEGIN {print $price - $bought_at}") # profit per share
  total_profit=$(awk "BEGIN {print $profit_per_share * $shares}")
  sum=$(awk "BEGIN {print $sum + $total_profit}")

  if [ "$price" != "null" ]; then
    printf "%-5s%-5d$COLOR_BOLD%8.2f$COLOR_RESET" $symbol $shares $price
    printf "$color%10.2f%12s$COLOR_RESET" $diff $(printf "(%.2f%%)" $percent)
    printf " %s " "$nonRegularMarketSign"
    printf " %10.2f" $profit_per_share 
    printf " %10.2f\n" $total_profit
  fi
done

printf '====================================================================\n'
printf "NET PROFIT (US$):\t\t\t\t\t%10.2f\n" $sum

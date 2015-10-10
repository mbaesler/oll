request    = require 'request'
moment     = require 'moment'
Pusher     = require 'pusher'
async      = require 'async'
express    = require 'express'
db         = require('arangojs')()
pusherConf = require './pusher-conf.json'
try pusher = new Pusher { appId: pusherConf.APP_ID, key: pusherConf.APP_KEY, secret: pusherConf.APP_SECRET }

app   = express()
users = db.collection 'users'
.then (col) ->
  users = col
, () ->
  console.log 'cant access users collection'
  processs.exit()



app.param 'cur', (req, res, next, currency) ->
  if currency.length isnt 3
    res.status(400).json {status:'ko', msg:'no valid currency'}
  else
    next()

app.param 'userid', (req, res, next, id) ->
  users.document id, (e, doc) ->
    if e?
      if e.code is 404 then res.status(404).json {status:'ko', msg:'cant find user'}
      else                  res.status(500).json {status:'ko', msg:'something went wrong'}
    else
      req.user = doc
      console.log doc
      console.log id
      next()



app.put '/api/:userid/:cur', (req, res) ->
  newCurrency    = req.params.cur
  userCurrencies = if req.user.currencies? then req.user.currencies else req.user.currencies = []

  if -1 < userCurrencies.indexOf newCurrency
    res.json {status:'ok', msg:'added currency'}
    return

  userCurrencies.push newCurrency

  users.update req.user._key, {currencies:userCurrencies}, (e) ->
    if e? then res.status(500).json {status:'ko', msg:'failed to add currency'}
    else       res.json {status:'ok', msg:'added currency'}


app.delete '/api/:userid/:cur', (req, res) ->
  delCurrency    = req.params.cur
  userCurrencies = if req.user.currencies? then req.user.currencies else req.user.currencies = []

  if -1 is index = userCurrencies.indexOf delCurrency
    res.json {status:'ok', msg:'deleted currency'}
    return

  userCurrencies.splice index, 1
  users.update req.user._key, {currencies:userCurrencies}, (e) ->
    if e? then res.status(500).json {status:'ko', msg:'failed to delete currency'}
    else       res.json {status:'ok', msg:'deleted currency'}



app.get '/api/:userid', (req, res) ->
  res.json {status:'ok', currencies: req.user.currencies or []}


app.listen 8080


timeoutRequest = () -> setTimout requestCurrencies, (60 - Number moment().format 'm') * 60 * 1000

request = (a, cb) ->
  cb null, {}, '{"Outcome":"Success","Message":null,"Identity":"Request","Delay":0.0083031,"Lines":[{"BaseCurrency":"EUR","Columns":[{"QuoteCurrency":"EUR","Rate":1.0},{"QuoteCurrency":"USD","Rate":1.137925},{"QuoteCurrency":"AUD","Rate":1.5641},{"QuoteCurrency":"JPY","Rate":135.2875}]},{"BaseCurrency":"USD","Columns":[{"QuoteCurrency":"EUR","Rate":0.886584},{"QuoteCurrency":"USD","Rate":1.0},{"QuoteCurrency":"AUD","Rate":1.386578},{"QuoteCurrency":"JPY","Rate":119.96}]},{"BaseCurrency":"AUD","Columns":[{"QuoteCurrency":"EUR","Rate":0.639345},{"QuoteCurrency":"USD","Rate":0.7212},{"QuoteCurrency":"AUD","Rate":1.0},{"QuoteCurrency":"JPY","Rate":86.525}]},{"BaseCurrency":"JPY","Columns":[{"QuoteCurrency":"EUR","Rate":0.00739167},{"QuoteCurrency":"USD","Rate":0.00833611},{"QuoteCurrency":"AUD","Rate":0.0115574},{"QuoteCurrency":"JPY","Rate":1.0}]}]}'


requestCurrencies = () ->
  db.query 'return unique(flatten(for u in users filter not_null(u.currencies) return u.currencies))', (e, cursor) ->
    return if e?

    cursor.all (e, result) ->
      return if e?

      request "https://globalcurrencies.xignite.com/xGlobalCurrencies.json/GetRealTimeRateTable?Symbols=#{result[0].join ','}&PriceType=Mid&_token=xxx", (e, res, body) ->
        return if e?

        try
          body = JSON.parse body
          return if body.Outcome isnt 'Success'

          eurToX = []

          for line in body.Lines
            if line.BaseCurrency is 'EUR'
              eurToX = line.Columns
              break

          db.query """
            FOR cur IN @currencies
              LET doc = document(currencies, cur.QuoteCurrency)

              FILTER IS_NULL(doc) OR cur.Rate > doc.rate

              UPSERT {_key:cur.QuoteCurrency}
              INSERT {_key:cur.QuoteCurrency, rate:cur.Rate}
              UPDATE {rate:cur.Rate} in currencies
              RETURN NEW
          """, {currencies:eurToX}, (e, cursor) ->
            return if e?

            cursor.all (e, results) ->
              return if e?

              async.eachSeries results, (currency, cb) ->
                try pusher.trigger "private-#{currency._key}", 'currency-peak', { message: "Currency #{currency._key} new peak at #{currency.rate}" }
                cb()


timeoutRequest()









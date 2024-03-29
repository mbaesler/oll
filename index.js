// Generated by CoffeeScript 1.10.0
var Pusher, app, async, db, express, moment, pusher, pusherConf, request, requestCurrencies, timeoutRequest, users;

request = require('request');

moment = require('moment');

Pusher = require('pusher');

async = require('async');

express = require('express');

db = require('arangojs')();

pusherConf = require('./pusher-conf.json');

try {
  pusher = new Pusher({
    appId: pusherConf.APP_ID,
    key: pusherConf.APP_KEY,
    secret: pusherConf.APP_SECRET
  });
} catch (undefined) {}

app = express();

users = db.collection('users').then(function(col) {
  return users = col;
}, function() {
  console.log('cant access users collection');
  return processs.exit();
});

app.param('cur', function(req, res, next, currency) {
  if (currency.length !== 3) {
    return res.status(400).json({
      status: 'ko',
      msg: 'no valid currency'
    });
  } else {
    return next();
  }
});

app.param('userid', function(req, res, next, id) {
  return users.document(id, function(e, doc) {
    if (e != null) {
      if (e.code === 404) {
        return res.status(404).json({
          status: 'ko',
          msg: 'cant find user'
        });
      } else {
        return res.status(500).json({
          status: 'ko',
          msg: 'something went wrong'
        });
      }
    } else {
      req.user = doc;
      console.log(doc);
      console.log(id);
      return next();
    }
  });
});

app.put('/api/:userid/:cur', function(req, res) {
  var newCurrency, userCurrencies;
  newCurrency = req.params.cur;
  userCurrencies = req.user.currencies != null ? req.user.currencies : req.user.currencies = [];
  if (-1 < userCurrencies.indexOf(newCurrency)) {
    res.json({
      status: 'ok',
      msg: 'added currency'
    });
    return;
  }
  userCurrencies.push(newCurrency);
  return users.update(req.user._key, {
    currencies: userCurrencies
  }, function(e) {
    if (e != null) {
      return res.status(500).json({
        status: 'ko',
        msg: 'failed to add currency'
      });
    } else {
      return res.json({
        status: 'ok',
        msg: 'added currency'
      });
    }
  });
});

app["delete"]('/api/:userid/:cur', function(req, res) {
  var delCurrency, index, userCurrencies;
  delCurrency = req.params.cur;
  userCurrencies = req.user.currencies != null ? req.user.currencies : req.user.currencies = [];
  if (-1 === (index = userCurrencies.indexOf(delCurrency))) {
    res.json({
      status: 'ok',
      msg: 'deleted currency'
    });
    return;
  }
  userCurrencies.splice(index, 1);
  return users.update(req.user._key, {
    currencies: userCurrencies
  }, function(e) {
    if (e != null) {
      return res.status(500).json({
        status: 'ko',
        msg: 'failed to delete currency'
      });
    } else {
      return res.json({
        status: 'ok',
        msg: 'deleted currency'
      });
    }
  });
});

app.get('/api/:userid', function(req, res) {
  return res.json({
    status: 'ok',
    currencies: req.user.currencies || []
  });
});

app.listen(8080);

timeoutRequest = function() {
  return setTimeout(requestCurrencies, (60 - Number(moment().format('m'))) * 60 * 1000);
};

requestCurrencies = function() {
  timeoutRequest();
  return db.query('return unique(flatten(for u in users filter not_null(u.currencies) return u.currencies))', function(e, cursor) {
    if (e != null) {
      return;
    }
    return cursor.all(function(e, result) {
      if (e != null) {
        return;
      }
      return request("https://globalcurrencies.xignite.com/xGlobalCurrencies.json/GetRealTimeRateTable?Symbols=" + (result[0].join(',')) + "&PriceType=Mid&_token=xxx", function(e, res, body) {
        var eurToX, i, len, line, ref;
        if (e != null) {
          return;
        }
        try {
          body = JSON.parse(body);
          if (body.Outcome !== 'Success') {
            return;
          }
          eurToX = [];
          ref = body.Lines;
          for (i = 0, len = ref.length; i < len; i++) {
            line = ref[i];
            if (line.BaseCurrency === 'EUR') {
              eurToX = line.Columns;
              break;
            }
          }
          return db.query("FOR cur IN @currencies\n  LET doc = document(currencies, cur.QuoteCurrency)\n\n  FILTER IS_NULL(doc) OR cur.Rate > doc.rate\n\n  UPSERT {_key:cur.QuoteCurrency}\n  INSERT {_key:cur.QuoteCurrency, rate:cur.Rate}\n  UPDATE {rate:cur.Rate} in currencies\n  RETURN NEW", {
            currencies: eurToX
          }, function(e, cursor) {
            if (e != null) {
              return;
            }
            return cursor.all(function(e, results) {
              if (e != null) {
                return;
              }
              return async.eachSeries(results, function(currency, cb) {
                try {
                  pusher.trigger("private-" + currency._key, 'currency-peak', {
                    message: "Currency " + currency._key + " new peak at " + currency.rate
                  });
                } catch (undefined) {}
                return cb();
              });
            });
          });
        } catch (undefined) {}
      });
    });
  });
};

timeoutRequest();

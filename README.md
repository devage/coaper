# coaper

CoAP implementation in erlang.
Currently CoAP packet parser/generater is only available.

## How to Use

First clone this repository.

```
$ git clone https://github.com/devage/coaper.git
```

Then run `erl` and test this code.

```
$ cd src
$ erl
  ...
1> c(coap).
2> rr(coap).
3> coap:parse(iolist_to_binary(coap:packit(
3> #coap_msg{ type=con, tkl=1, code=get, mid=16#1234, token=[16#01],
3> options=[#coap_opt{type='uri-path', value="test"}] }))).
```

The content inside `#coap_msg{}` record means `CON GET /test [0x1234]` and its token is `0x01`.
And the following is the result.

```
#coap_msg{uri = undefined,delta = 11,ver = 1,type = con,
          tkl = 1,code = get,mid = 4660,
          token = [1],
          options = [#coap_opt{type = 'uri-path',value = "test"}],
          payload = undefined}
```

## To Do

- CON/NON transfer
- Block-wise transfer ([draft-ietf-core-block-19](https://tools.ietf.org/html/draft-ietf-core-block-19))
- Observation ([RFC 7641](https://tools.ietf.org/html/rfc7641))
- Link Format ([RFC 6690](https://tools.ietf.org/html/rfc6690))
- Proxy ([RFC 7252](https://tools.ietf.org/html/rfc7252), [draft-ietf-core-http-mapping-08](https://tools.ietf.org/html/draft-ietf-core-http-mapping-08))

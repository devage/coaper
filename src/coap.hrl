-define(COAPPORT, 5683).

% retransmission
-define(ACK_TIMEOUT, 2000).
-define(ACK_RANDOM_FACTOR, 1.5).
-define(MAX_RETRANS, 4).

-record(coap_msg, {
          % meta
          uri,
          delta = 0,

          % packet fields
          ver = 1,
          type,
          tkl,
          code,
          mid = 0,
          token = [],
          options = [],
          payload % after `0xff' byte
         }).

-record(coap_opt, { type, value }).

-record(payload, {type, data }).

-module(coaper).
-author("ikpark@gmail.com").

-include("coaper.hrl").

-export([packit/1, parse/1]).

%% export

packit(Msg) ->
  packit(header, Msg).

parse(Packet) ->
  parse(header, Packet, #coap_msg{}).

%% private

packit(header, Msg) ->
  #coap_msg{ ver = V, type = T, tkl = Tkl, code = C, mid = Mid } = Msg,
  Type = type_val(T),
  Code = code_val(C),
  Header = [<<V:2, Type:2, Tkl:4, Code:8, Mid:16>>],
  [Header | packit(token, Msg)];
packit(token, Msg) ->
  #coap_msg{ token = Token } = Msg,
  [Token | packit(options, Msg)];
packit(options, Msg) ->
  #coap_msg{ options = O } = Msg,
  Opts = packit_options(lists:sort(fun(A, B) ->
                                       Ta = option_type_val(A#coap_opt.type),
                                       Tb = option_type_val(B#coap_opt.type),
                                       Ta =< Tb
                                   end, O)),
  [Opts | packit(payload, Msg)];
packit(payload, #coap_msg{ payload = undefined }) ->
  [];
packit(payload, #coap_msg{ payload = #payload{ data = Data }}) ->
  [16#ff, Data].

packit_options(Opts) ->
  packit_options(Opts, 0).

packit_options([], _Last) -> [];
packit_options([H|Rest], Last) ->
  T = option_type_val(H#coap_opt.type),
  O = packit_option(H, Last),
  [O | packit_options(Rest, T)].

packit_option([], _Last) -> [];
packit_option(#coap_opt{ type = 'content-format', value = V }, Last) ->
  Val = content_format_val(V),
  packit_option(option_type_val('content-format') - Last, get_uint_len(Val), Val);
packit_option(#coap_opt{ type = T, value = V }, Last) when is_number(V) ->
  packit_option(option_type_val(T) - Last, get_uint_len(V), V);
packit_option(#coap_opt{ type = T, value = V }, Last) ->
  packit_option(option_type_val(T) - Last, length(V), V).

packit_option(Type, Len, Val) ->
  lists:foldl(fun(F, { T1, L1, V1 }) -> F(T1, L1, V1) end,
              { Type, Len, Val },
              % length
              [fun(T, L, V) when L > 268 -> { T, 14, [<<(L-269):16>> | V] };
                  (T, L, V) when L >  12 -> { T, 13, [<<(L- 13):8 >> | V] };
                  (T, L,_V) when L ==  0 -> { T,  L, [] };
                  (T, L, V)              -> { T,  L, V }
               end,
               % type
               fun(T, L, V) when T > 268 -> { 14, L, [<<(T-269):16>> | V] };
                  (T, L, V) when T >  12 -> { 13, L, [<<(T- 13):8 >> | V] };
                  (T, L, V)              -> { T,  L, V }
               end,
               % pack it
               fun(T, L, V) -> [<<T:4, L:4>>, V] end]).

get_uint_len(0) -> 0;
get_uint_len(V) ->
  byte_size(binary:encode_unsigned(V)).

parse(header, Bin, Msg) ->
  <<Ver:2, Type:2, Tkl:4, Code:8, Mid:16, Rest/binary>> = Bin,
  parse(token, Rest, Msg#coap_msg{
                       ver = Ver, type = type(Type),
                       tkl = Tkl, code = code(Code), mid = Mid });
parse(token, Bin, Msg) ->
  Len = Msg#coap_msg.tkl * 8,
  <<Token:Len, Rest/binary>> = Bin,
  parse(options, Rest, Msg#coap_msg{
                         token = binary_to_list(<<Token:Len>>) });
parse(options, <<>>, Msg) ->
  Msg;
parse(options, <<16#ff:8, Bin/binary>>, Msg) ->
  parse(payload, Bin, Msg);
parse(options, Bin, Msg) ->
  % XXX
  { T, V, Rest } = parse_option(Bin),
  Delta  = Msg#coap_msg.delta,
  Opts   = Msg#coap_msg.options,
  Type   = option_type(T + Delta),
  Value  = parse_option_val(Type, V),
  NewOpt = #coap_opt{ type  = Type, value = Value },
  parse(options, Rest, Msg#coap_msg{
                         options = lists:append(Opts, [NewOpt]),
                         delta = T + Delta });
parse(payload, Bin, Msg) ->
  Type = find_option(Msg#coap_msg.options, 'content-format'),
  Data = case Type of
           'application/octet-stream' -> Bin;
           'application/exi' -> Bin;
           _ -> binary_to_list(Bin)
         end,
  Msg#coap_msg{ payload = #payload{ type = Type, data = Data }}.

parse_option(<<T:4, L:4, V/binary>>) ->
  { Type, Len, Bin } = parse_option(T, L, V),
  case Len of
    0 ->
      { Type, <<0:8>>, Bin };
    _ ->
      BitLen = Len * 8,
      <<Val:BitLen/bits, Rest/binary>> = Bin,
      { Type, Val, Rest }
  end.

parse_option(13, L, <<T:8,  Rest/binary>>) -> parse_option(T +  13, L, Rest);
parse_option(14, L, <<T:16, Rest/binary>>) -> parse_option(T + 269, L, Rest);
parse_option(T,  0, <<>>) -> { T, 0, <<>> };
parse_option(T, 13, <<L:8,  Rest/binary>>) -> parse_option(T, L +  13, Rest);
parse_option(T, 14, <<L:16, Rest/binary>>) -> parse_option(T, L + 269, Rest);
parse_option(T, L, Rest) -> { T, L, Rest }.

parse_option_val('content-format', <<V:8>>) ->
  content_format(V);
parse_option_val(_T, V) ->
  binary_to_list(V).

find_option([], _Type) -> 'null';
find_option([H|_Rest], Type) when H#coap_opt.type == Type -> H#coap_opt.value;
find_option([_H|Rest], Type) -> find_option(Rest, Type).

type(0) -> con;
type(1) -> non;
type(2) -> ack;
type(3) -> rst.

type_val(con) -> 0;
type_val(non) -> 1;
type_val(ack) -> 2;
type_val(rst) -> 3.

code(0) -> empty;
code(1) -> get;
code(2) -> post;
code(3) -> put;
code(4) -> delete;
code(16#41) -> '2.01';
code(16#42) -> '2.02';
code(16#43) -> '2.03';
code(16#44) -> '2.04';
code(16#45) -> '2.05';
code(16#80) -> '4.00';
code(16#81) -> '4.01';
code(16#82) -> '4.02';
code(16#83) -> '4.03';
code(16#84) -> '4.04';
code(16#85) -> '4.05';
code(16#86) -> '4.06';
code(16#8c) -> '4.12';
code(16#8d) -> '4.13';
code(16#8f) -> '4.15';
code(16#a0) -> '5.00';
code(16#a1) -> '5.01';
code(16#a2) -> '5.02';
code(16#a3) -> '5.03';
code(16#a4) -> '5.04';
code(16#a5) -> '5.05'.

code_val(empty)  -> 0;
code_val(get)    -> 1;
code_val(post)   -> 2;
code_val(put)    -> 3;
code_val(delete) -> 4;
code_val('2.01') -> 16#41;
code_val('2.02') -> 16#42;
code_val('2.03') -> 16#43;
code_val('2.04') -> 16#44;
code_val('2.05') -> 16#45;
code_val('4.00') -> 16#80;
code_val('4.01') -> 16#81;
code_val('4.02') -> 16#82;
code_val('4.03') -> 16#83;
code_val('4.04') -> 16#84;
code_val('4.05') -> 16#85;
code_val('4.06') -> 16#86;
code_val('4.12') -> 16#8c;
code_val('4.13') -> 16#8d;
code_val('4.15') -> 16#8f;
code_val('5.00') -> 16#a0;
code_val('5.01') -> 16#a1;
code_val('5.02') -> 16#a2;
code_val('5.03') -> 16#a3;
code_val('5.04') -> 16#a4;
code_val('5.05') -> 16#a5.

option_type(1)  -> 'if-match';
option_type(3)  -> 'uri-host';
option_type(4)  -> 'etag';
option_type(5)  -> 'if-no-match';
option_type(6)  -> 'observe';
option_type(7)  -> 'uri-port';
option_type(8)  -> 'location-path';
option_type(11) -> 'uri-path';
option_type(12) -> 'content-format';
option_type(14) -> 'max-age';
option_type(15) -> 'uri-query';
option_type(17) -> 'accept';
option_type(20) -> 'location-query';
option_type(23) -> 'block2';
option_type(27) -> 'block1';
option_type(28) -> 'size2';
option_type(35) -> 'proxy-uri';
option_type(39) -> 'proxy-scheme';
option_type(60) -> 'size1';
option_type(T)  -> T.

option_type_val('if-match')       -> 1;
option_type_val('uri-host')       -> 3;
option_type_val('etag')           -> 4;
option_type_val('if-no-match')    -> 5;
option_type_val('observe')        -> 6;
option_type_val('uri-port')       -> 7;
option_type_val('location-path')  -> 8;
option_type_val('uri-path')       -> 11;
option_type_val('content-format') -> 12;
option_type_val('max-age')        -> 14;
option_type_val('uri-query')      -> 15;
option_type_val('accept')         -> 17;
option_type_val('location-query') -> 20;
option_type_val('block2')         -> 23;
option_type_val('block1')         -> 27;
option_type_val('size2')          -> 28;
option_type_val('proxy-uri')      -> 35;
option_type_val('proxy-scheme')   -> 39;
option_type_val('size1')          -> 60.

content_format(0)  -> 'text/plain;charset=utf-8';
content_format(40) -> 'application/link-format';
content_format(41) -> 'application/xml';
content_format(42) -> 'application/octet-stream';
content_format(47) -> 'application/exi';
content_format(50) -> 'application/json';
content_format(_V) -> 'null'.

content_format_val('text/plain;charset=utf-8') -> 0;
content_format_val('application/link-format')  -> 40;
content_format_val('application/xml')          -> 41;
content_format_val('application/octet-stream') -> 42;
content_format_val('application/exi')          -> 47;
content_format_val('application/json')         -> 50.

to_string(type, Type) ->
  string:to_upper(atom_to_list(Type));
to_string(code, empty)  -> "EMPTY";
to_string(code, get)    -> "GET";
to_string(code, put)    -> "PUT";
to_string(code, post)   -> "POST";
to_string(code, delete) -> "DELETE";
to_string(code, '2.01') -> "Created";
to_string(code, '2.02') -> "Deleted";
to_string(code, '2.03') -> "Valid";
to_string(code, '2.04') -> "Changed";
to_string(code, '2.05') -> "Content";
to_string(code, '4.00') -> "Bad Request";
to_string(code, '4.01') -> "Unauthorized";
to_string(code, '4.02') -> "Bad Option";
to_string(code, '4.03') -> "Forbidden";
to_string(code, '4.04') -> "Not Found";
to_string(code, '4.05') -> "Method Not Allowed";
to_string(code, '4.06') -> "Not Acceptable";
to_string(code, '4.12') -> "Precondition Failed";
to_string(code, '4.13') -> "Request Ent. Too Large";
to_string(code, '4.15') -> "Unsupported Media Type";
to_string(code, '5.00') -> "Internal Server Error";
to_string(code, '5.01') -> "Not Implemented";
to_string(code, '5.02') -> "Bad Gateway";
to_string(code, '5.03') -> "Service Unavailable";
to_string(code, '5.04') -> "Gateway Timeout";
to_string(code, '5.05') -> "Proxying Not Supported";
to_string(option, OptType) -> atom_to_list(OptType);
to_string(content_format, Cf) -> atom_to_list(Cf).

%% EUnit tests

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

parse_option_test() ->
  ?assertEqual({   1,   1, <<>> }, parse_option(<< 1:4,  1:4>>)),
  ?assertEqual({  14,   1, <<>> }, parse_option(<<13:4,  1:4, 1:8>>)),
  ?assertEqual({ 270,   1, <<>> }, parse_option(<<14:4,  1:4, 1:16>>)),
  ?assertEqual({   1,  14, <<>> }, parse_option(<< 1:4, 13:4, 1:8>>)),
  ?assertEqual({   1, 270, <<>> }, parse_option(<< 1:4, 14:4, 1:16>>)),
  ?assertEqual({  14,  14, <<>> }, parse_option(<<13:4, 13:4, 1:8,  1:8>>)),
  ?assertEqual({  14, 270, <<>> }, parse_option(<<13:4, 14:4, 1:8,  1:16>>)),
  ?assertEqual({ 270,  14, <<>> }, parse_option(<<14:4, 13:4, 1:16  1:8>>)),
  ?assertEqual({ 270, 270, <<>> }, parse_option(<<14:4, 14:4, 1:16, 1:16>>)).

-endif.

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:convert' show utf8, latin1, json;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf.dart' show Response;
import 'package:shelf/shelf_io.dart' show serve;
import 'package:shelf_static/shelf_static.dart' show createStaticHandler;
import 'package:pointycastle/impl.dart';
import 'package:pointycastle/export.dart';
import 'package:pointycastle/key_generators/rsa_key_generator.dart' show RSAKeyGenerator;
import 'package:basic_utils/basic_utils.dart' show X509Utils;
import 'product.dart';

final String products = json.encode(
  {
    'Salato': [
      Product.constant(
        'PANINO ONTO.jpg',
        'PANINO ONTO',
        450
      ),
      Product.constant(
        'Patatine-Fritte.jpg',
        'PATATINE FRITTE',
        200
      ),
      Product.constant(
        'MENÙ ONTO.jpeg',
        'MENÙ ONTO',
        650
      )
    ],
    'Dolce': [
      Product.constant(
        'Zucchero Filato.jpeg',
        'ZUCCHERO FILATO',
        100
      ),
      Product.constant(
        'POPCORN.jpg',
        'POPCORN',
        200
      ),
      Product.constant(
        'cioccolata-calda-densa.jpg',
        'CIOCCOLATA CALDA',
        100
      ),
      Product.constant(
        'pandoro.PNG',
        'PANDORO',
        100
      )
    ]
  }
);

final List<File> printers = [];
final shelf.Handler fileHandler = createStaticHandler('.', defaultDocument: 'index.html');

String pubKey;
RSAPrivateKey privKey;
final PKCS1Encoding rsa = PKCS1Encoding(RSAEngine());

void main() async {
  {
    File pubKeyFile = File('pub.pem');
    File privKeyFile = File('priv.pem');
    //Loading KeyPair
    if(await pubKeyFile.exists() || await privKeyFile.exists()){
      print('Loading key pair');
      pubKey = await pubKeyFile.readAsString();
      privKey = X509Utils.privateKeyFromPem(await privKeyFile.readAsString());
    } else {
      //Creating KeyPair
      print('Creating key pair');
      var rng = Random.secure();
      var seeds = Uint8List(32);
      for(var i = 0; i < seeds.length; ++i) seeds[i]=rng.nextInt(256);
      var keyPair = (
        RSAKeyGenerator()..init(
          ParametersWithRandom(
            RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 5),
            FortunaRandom()..seed(KeyParameter(seeds))
          )
        )
      ).generateKeyPair();
      privKey = keyPair.privateKey;
      pubKey = X509Utils.encodeRSAPublicKeyToPem(keyPair.publicKey);
      await privKeyFile.writeAsString(X509Utils.encodeRSAPrivateKeyToPem(keyPair.privateKey), flush: true);
      await pubKeyFile.writeAsString(pubKey, flush: true);
    }
  }
  rsa.init(false, PrivateKeyParameter<RSAPrivateKey>(privKey));

  //Putting printers in list
  printers.addAll(
    Directory('/dev/usb').listSync(followLinks: false)
      .where((e)=>e.path.contains('/lp') && e is File)
      .cast<File>()
  );

  var handler = shelf.Pipeline().addMiddleware(shelf.logRequests()).addHandler(reqHandler);

  await serve(handler, '0.0.0.0', 8080).then(
    (server) => print('Listening on ${server.address.address}:${server.port}')
  );
}

FutureOr<Response> reqHandler(shelf.Request req) async {
  switch (req.url.path) {
    case 'print':
      int idxPrinter;
      //Bad request
      if(
        !req.url.hasQuery || 
        req.url.queryParameters['p'] == null ||
        (idxPrinter = int.tryParse(req.url.queryParameters['p'])) == null ||
        idxPrinter < 0 ||
        idxPrinter >= printers.length
      ) return Response(400, body: 'Missing printer index');

      //Decode the body
      Uint8List bytes;
      await req.read().forEach(
        (stream){
          if(bytes == null)bytes = Uint8List.fromList(stream);
          else bytes.addAll(stream);
        }
      );
      dynamic out = Uint8List(bytes.length);
      int length = rsa.processBlock(
        bytes,
        0, out.length,
        out, 0
      );

      //Decode and deserialize the body
      try {
        out = json.decode(utf8.decode(out.sublist(0, length))) as List<dynamic>;
      } on Exception {
        return Response(400, body: 'Invalid body');
      }
      out = <Item>[
        for (var item in out) 
          Item.fromJson(item)
      ];
      
      //Actually print the thing
      printerPrint(printers[idxPrinter], out);
      return Response.ok('Printing');
      break;
    case 'key':
      return Response.ok(pubKey);
      break;
    case 'products':
      return Response.ok(products);
      break;
    case 'printers':
      return Response.ok(
        printers.map(
          (e)=>e.path,
        ).join(',')
      );
      break;
    default:
      return fileHandler(req);
  }
}

void printerPrint(File printer, int orderNum, List<Item> items) async {
  const int ESC = 0x1B;
  var bytes = List<int>();
  bytes.addAll([ESC, 0x40]);
  bytes.addAll([ESC, 0x61, 2]);
  bytes.addAll(latin1.encode('$orderNum\nAssemblea di Natale\n'));
  bytes.addAll([ESC, 0x61, 0]);
  for (Item item in items){
    bytes.addAll(
      latin1.encode('${item.product.name} x${item.quantity}\n')
    );
    for (MapEntry<String, dynamic> e in item.chosvar.entries) {
      bytes.addAll(latin1.encode('\t${e.key}:'));
      if(e.value is String) bytes.addAll(latin1.encode('${e.value}\n'));
      else {
        for (String choice in e.value)
          bytes.addAll(latin1.encode('\n\t\t$choice'));
        bytes.addAll(latin1.encode('\n'));
      }
    }
  }
  bytes.addAll([ESC, 0x61, 2]);
  bytes.addAll(latin1.encode('Totale: ${prettyPrintPrice(intTotal(items))} Euro\n'));
  bytes.addAll([0x1D, 0x56, 1]);
  await printer.writeAsBytes(bytes);
}
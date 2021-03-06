import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert' show utf8, latin1, json;
import 'package:basic_utils/basic_utils.dart' show X509Utils;
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/asymmetric/rsa.dart';
import 'package:pointycastle/export.dart';
import 'package:pointycastle/pointycastle.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf.dart' show Response;
import 'package:shelf/shelf_io.dart' show serve;
import 'package:shelf_static/shelf_static.dart' show createStaticHandler;
import 'package:csv/csv.dart' show CsvCodec;
import 'product.dart';
import 'utils.dart';

final CsvCodec csv = CsvCodec();

void main() async {
  try {
    await run();
  } on Exception catch(e) {
    print(e.toString());
    exit(1);
  }
}

void run() async {
  //Load RSA Keys
  RSAPrivateKey priv;
  String pub;
  {
    File privFile = File('priv.pem');
    File pubFile = File('pub.pem');
    if(await privFile.exists() && await pubFile.exists()){
      print('Loading keys');
      pub = await pubFile.readAsString();
      priv = X509Utils.privateKeyFromPem(await privFile.readAsString());
    } else {
      print('Creating keys');
      dynamic keys = RSAKeyGenerator()..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.from(65537), 4096, 12),
          DartRandomSecure()
        )
      );
      keys = keys.generateKeyPair();
      pub = X509Utils.encodeRSAPublicKeyToPem(keys.publicKey);
      await pubFile.writeAsString(pub);
      await privFile.writeAsString(X509Utils.encodeRSAPrivateKeyToPem(keys.privateKey));
      priv = keys.privateKey;
    }
  }

  //Putting printers in list
  final List<File> printers = [];
  try {
    await for (var entity in Directory('/dev/usb').list(followLinks: false))
      if(entity.path.contains('/lp') && entity is File)
        printers.add(entity);
  } on FileSystemException {
  } finally {
    printers.add(File('/dev/null'));
  }

  //Initializing csv and order in-memory database
  int currentOrder = 0;
  Map<int, List<Item>> data = {};
  {
    File csvdata = File('data.csv');
    if(await csvdata.exists()){
      List<List> table = csv.decoder.convert(await csvdata.readAsString(), shouldParseNumbers: true);
      try {
        currentOrder = table.last[0] is int ? table.last[0]+1 : 0;
      } on StateError {
        currentOrder = 0;
      }
    } else {
      await csvdata.create();
      await csvdata.writeAsString(
        csv.encoder.convert(
          [['Order Number', 'Product', 'Variant(s)', 'Quantity']]
        )
      );
    }
  }
  print('Current Order Number: $currentOrder');

  var handler = shelf.Pipeline().addMiddleware(shelf.logRequests())
    .addHandler(
      reqHandler(
        data: data,
        currentOrder: currentOrder,
        staticFilesHandler: createStaticHandler('.', defaultDocument: 'index.html'),
        priv: priv,
        pub: pub,
        products: await File('product.json').readAsString(),
        printers: printers
      )
    );

  HttpServer server = await serve(handler, '0.0.0.0', 8080);
  print('Listening on ${server.address.address}:${server.port}');

  StreamSubscription sub;
  sub = ProcessSignal.sigint.watch().listen(
    (sig) async {
      await server.close();
      storeToFile(data);
      await sub.cancel();
    }
  );
}

shelf.Handler reqHandler(
  {
    RSAPrivateKey priv,
    String pub,
    Map<int, List<Item>> data,
    int currentOrder = 0,
    shelf.Handler staticFilesHandler,
    List<File> printers,
    String products
  }
){
  OAEPEncoding enc = OAEPEncoding(
    RSAEngine()
  )..init(
    false,
    PrivateKeyParameter<RSAPrivateKey>(priv)
  );
  return (shelf.Request req) async {
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

        //Read the body
        List out = json.decode(await req.readAsString()) as List;

        //Decrypt, decode and deserialize the body
        try {
          out = json.decode(
            utf8.decode(
              out.fold(
                <int>[],
                (init, e)=>init..addAll(
                  enc.process(Uint8List.fromList(e.cast<int>()))
                )
              )
            )
          ) as List;
        } on Exception {
          return Response(400, body: 'Invalid body');
        }
        out = <Item>[
          for (var item in out) 
            Item.fromJson(item)
        ];
        
        //Actually print the thing
        int currN = currentOrder++;
        data[currN] = out;
        await printerPrint(printers[idxPrinter], currN, out);
        return Response.ok('Printed');
        break;
      case 'key':
        return Response.ok(pub);
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
        return staticFilesHandler(req);
    }
  };
}

void printerPrint(File printer, int orderNum, List<Item> items) async {
  const int ESC = 0x1B;
  var bytes = <int>[];
  bytes.addAll([ESC, 0x40]);
  bytes.addAll([ESC, 0x61, 2]);
  bytes.addAll(latin1.encode('$orderNum\nAssemblea di Natale\n'));
  bytes.addAll([ESC, 0x61, 0]);
  for (Item item in items){
    bytes.addAll(
      latin1.encode('${item.product.name} x${item.quantity}\n')
    );
    if(item.chosvar != null)
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

void storeToFile(Map<int, List<Item>> map) async =>
  await File('data.csv').writeAsString(
    csv.encoder.convert(
      [
        for (MapEntry<int, List<Item>> e in map.entries)[
          e.key,
          for (Item i in e.value) ...[
            i.product.name,
            i.chosvar.toString(),
            i.quantity
          ]
        ]//[['Order Number', 'Product', 'Variant(s)', 'Quantity']]
      ]
    )+'\n',
    mode: FileMode.writeOnlyAppend
  );
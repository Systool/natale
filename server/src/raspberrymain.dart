import 'dart:async';
import 'dart:io';
import 'dart:convert' show utf8, latin1, json;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf.dart' show Response;
import 'package:shelf/shelf_io.dart' show serve;
import 'package:shelf_static/shelf_static.dart' show createStaticHandler;
import 'package:csv/csv.dart' show CsvCodec;
import 'product.dart';
import 'utils.dart';

final String products = json.encode(
  {
    'Salato':[
      Product.constant(
        'MENÙ ONTO.jpeg',
        'MENU ONTO',
        650,
        {
          'Carne': VariationList(
            ListKind.Radio,
            [
              'Porchetta',
              'Salsiccia',
              'No Carne'
            ]
          ),
          'Farcitura':  VariationList(
            ListKind.Check,
            [
              'Cipolla',
              'Peperoni',
              'Formaggio',
              'Maionese',
              'Ketchup'
            ]
          ),
          'Salsa': VariationList(
            ListKind.Check,
            [
              'Ketchup',
              'Maionese'
            ]
          ),
          '': VariationList(
            ListKind.Radio,
            [
              'Coca Cola',
              'Fanta',
              'Sprite',
              'The Limone',
              'The Pesca'
            ]
          )
        }
      ),
      Product.constant(
        'PANINO ONTO.jpg',
        'PANINO ONTO',
        450,
        {
          'Carne': VariationList(
            ListKind.Radio,
            [
              'Porchetta',
              'Salsiccia',
              'No Carne'
            ]
          ),
          'Farcitura':  VariationList(
            ListKind.Check,
            [
              'Cipolla',
              'Peperoni',
              'Formaggio',
              'Maionese',
              'Ketchup'
            ]
          )
        }
      ),
      Product.constant(
        'Patatine-Fritte.jpg',
        'PATATINE FRITTE',
        200,
        {
          'Salsa': VariationList(
            ListKind.Check,
            [
              'Ketchup',
              'Maionese'
            ]
          )
        }
      ),
      Product.constant(
          'POPCORN.jpg',
          'POPCORN',
          200
      )
    ],
    'Dolce': [
      Product.constant(
        'Zucchero Filato.jpeg',
        'ZUCCHERO FILATO',
        100
      ),
      Product.constant(
        'pandoro.PNG',
        'PANDORO',
        100
      ),
      Product.constant(
        'cioccolata-calda-densa.jpg',
        'CIOCCOLATA CALDA',
        100
      ),
      Product.constant(
        'menu dolce.PNG',
        'MENU DOLCE',
        150
      )
    ],
    'Bibite': [
      Product.constant(
        'bibite.jpeg',
        'BIBITE',
        80,
        {
          '': VariationList(
            ListKind.Radio,
            [
              'Coca Cola',
              'Fanta',
              'Sprite',
              'The Limone',
              'The Pesca'
            ]
          )
        }
      )
    ]
  }
);

final List<MutexPair<File>> printers = [];
final shelf.Handler fileHandler = createStaticHandler('.', defaultDocument: 'index.html');
final CsvCodec csv = CsvCodec(eol: '\n');

void main() async {
  //Putting printers in list
  printers.addAll(
    Directory('/dev/usb').listSync(followLinks: false)
      .where((e)=>e.path.contains('/lp') && e is File)
      .map((e)=>MutexPair(e as File))
  );

  //Initializing csv and order in-memory database
  int currentOrder = 0;
  {
    File csvdata = File('data.csv');
    if(await csvdata.exists()){
      List<List> table = csv.decoder.convert(await csvdata.readAsString(), shouldParseNumbers: true);
      currentOrder = table.last[0] is int ? table.last[0]+1 : 0;
    } else {
      await csvdata.create();
      await csvdata.writeAsString(
        csv.encoder.convert(
          [['Order Number', 'Product', 'Variant(s)', 'Quantity']]
        )
      );
    }
  }
  MutexPair<IOSink> csvdata = MutexPair(await File('data.csv').openWrite(mode: FileMode.append));

  var handler = shelf.Pipeline().addMiddleware(shelf.logRequests())
    .addHandler(
      reqHandler(
        getCurrentOrderNumber: ()=>currentOrder++,
        outFile: csvdata
      )
    );

  HttpServer server = await serve(handler, '0.0.0.0', 8080).then(
    (server){
      print('Listening on ${server.address.address}:${server.port}');
      return server;
    }
  );
  print(currentOrder);

  StreamSubscription sub;
  sub = ProcessSignal.sigint.watch().listen(
    (sig) async {
      await server.close();
      await sub.cancel();
      await csvdata.res.flush();
      await csvdata.res.close();
      print(currentOrder);
    }
  );
}

shelf.Handler reqHandler(
  {
    Map<int, List<Item>> data,
    int Function() getCurrentOrderNumber,
    MutexPair<IOSink> outFile
  }
) =>
  (shelf.Request req) async {
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

        //Decode and deserialize the body
        dynamic out;
        try {
          out = json.decode(await req.readAsString()) as List<dynamic>;
        } on Exception {
          return Response(400, body: 'Invalid body');
        }
        out = <Item>[
          for (var item in out) 
            Item.fromJson(item)
        ];
        
        //Actually print the thing
        int currN = getCurrentOrderNumber();
        await printers[idxPrinter].lock.synchronized(
          () async => await printerPrint(printers[idxPrinter].res, currN, out)
        );
        await outFile.lock.synchronized(
          () async => await storeRow(outFile.res, currN, out)
        );
        return Response.ok('Printed');
        break;
      case 'products':
        return Response.ok(products);
        break;
      case 'printers':
        return Response.ok(
          printers.map(
            (e)=>e.res.path,
          ).join(',')
        );
        break;
      default:
        return fileHandler(req);
    }
  };

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

void storeRow(IOSink out, int orderN, List<Item> row) async {
  if(row.isNotEmpty){
    StringBuffer sb = StringBuffer();
    csv.encoder.convertSingleRow(
      sb,
      [
        orderN,
        for (Item i in row) ...[
          i.product.name,
          i.chosvar.toString(),
          i.quantity
        ]
      ]
    );
    sb.write('\n');
    //[['Order Number', 'Product', 'Variant(s)', 'Quantity']]
    out.write(sb);
  }
}
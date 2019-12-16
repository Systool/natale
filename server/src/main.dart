import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert' show utf8, latin1, json;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf.dart' show Response;
import 'package:shelf/shelf_io.dart' show serve;
import 'package:shelf_static/shelf_static.dart' show createStaticHandler;
import 'package:csv/csv.dart' show CsvCodec;
import 'product.dart';

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
      ),
      Product.constant(
          'bibite.jpeg',
          'BIBITA',
          0,
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
          'Bibite': VariationList(
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
  } as Map
);

final List<File> printers = [];
final shelf.Handler fileHandler = createStaticHandler('.', defaultDocument: 'index.html');
final CsvCodec csv = CsvCodec();

void main() async {
  //Putting printers in list
  printers.addAll(
    Directory('/dev/usb').listSync(followLinks: false)
      .where((e)=>e.path.contains('/lp') && e is File)
      .cast<File>()
  );

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
  print(currentOrder);

  var handler = shelf.Pipeline().addMiddleware(shelf.logRequests())
    .addHandler(
      reqHandler(
        data: data,
        getCurrentOrderNumber: ()=>currentOrder++
      )
    );

  HttpServer server = await serve(handler, '0.0.0.0', 8080).then(
    (server){
      print('Listening on ${server.address.address}:${server.port}');
      return server;
    }
  );

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
    Map<int, List<Item>> data,
    int Function() getCurrentOrderNumber
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

        //Decode the body
        Uint8List body;
        await req.read().forEach(
          (stream){
            if(body == null)body = Uint8List.fromList(stream);
            else body.addAll(stream);
          }
        );
        dynamic out;

        //Decode and deserialize the body
        try {
          out = json.decode(utf8.decode(body)) as List<dynamic>;
        } on Exception {
          return Response(400, body: 'Invalid body');
        }
        out = <Item>[
          for (var item in out) 
            Item.fromJson(item)
        ];
        
        //Actually print the thing
        int currN = getCurrentOrderNumber();
        data[currN] = out;
        await printerPrint(printers[idxPrinter], currN, out);
        return Response.ok('Printed');
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
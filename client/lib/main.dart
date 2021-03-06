import 'dart:async';
import 'dart:html' show window;
import 'dart:convert' show json, utf8;
import 'dart:typed_data';
import 'dart:ui' hide window;
import 'dart:math' show min;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:http/browser_client.dart' show BrowserClient;
import 'package:basic_utils/basic_utils.dart' show X509Utils;
import 'package:pointycastle/asymmetric/oaep.dart';
import 'package:pointycastle/asymmetric/rsa.dart';
import 'package:pointycastle/pointycastle.dart' hide Padding;
import 'product.dart';
import 'delegates.dart';

final httpClient = BrowserClient();
final rsa = OAEPEncoding(RSAEngine());
final Map<String, List<Product>> prodotti = {};
int idxPrinter;

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Assemblea di Natale',
      theme: ThemeData(
        primarySwatch: Colors.red,
        textTheme: TextTheme(
          body1: TextStyle(
            fontFamily: "prod",
            color: Colors.black,
            fontSize: 16
          ),
          body2: TextStyle(
            fontFamily: "Roboto",
            color: Colors.black,
            fontSize: 16
          )
        )
      ),
      home: Config(),
    );
  }
}

class Config extends StatelessWidget {
  final storingProducts = (
    ()async{
      dynamic resp = await httpClient.get(Uri.http(window.location.host, 'products'));
      resp = json.decode(resp.body);

      if(resp is Map<String, dynamic>)
        for (MapEntry<String, dynamic> e in resp.entries)
          prodotti[e.key] = [
            for (var prod in e.value)
              Product.fromJson(prod)
          ];
      else throw StateError('Products were not sent correctly');
    }
  )();

  final storingKey = (
    ()async{
      String resp = (await httpClient.get(Uri.http(window.location.host, 'key'))).body;
      rsa.init(
        true,
        PublicKeyParameter(X509Utils.publicKeyFromPem(resp))
      );
    }
  )();

  Widget build(BuildContext cntxt) => Scaffold(
    body: Center(
      child: StatefulBuilder(
        builder: (cntxt, setState)=>idxPrinter == null ?
          FutureBuilder<List<String>>(
            future: httpClient.get(Uri.http(window.location.host, "printers")).then(
              (resp)=>resp.body.split(",")..removeWhere((s)=>s.isEmpty)
            ),
            builder: (cntxt, future)=>future.connectionState == ConnectionState.done ?
              future.hasData ? ListView.builder(
                shrinkWrap: true,
                itemCount: future.data.length,
                itemBuilder: (cntxt, idx)=>RaisedButton(
                  child: Text(future.data[idx]),
                  onPressed: (){
                    idxPrinter = idx;
                    setState((){});
                  },
                ),
              )
              : Text("Error: ${future.error.toString()}")
            : Text("Getting Printers from ${window.location.host}...", textScaleFactor: 1.5),
          )
          :FutureBuilder(
            future: Future.wait([storingProducts, storingKey]),
            builder: (cntxt, future){
              if(future.connectionState == ConnectionState.done)
                if(future.hasError) return Text("Error: ${future.error.toString()}");
                else {
                  SchedulerBinding.instance.addPostFrameCallback(
                    (_)=>Navigator.pushReplacement(cntxt, CupertinoPageRoute(builder: (cntxt)=>Landing()))
                  );
                  return SizedBox.expand(child: Container(color: Colors.transparent));
                }
                else return Text("Getting Products from ${window.location.host}...", textScaleFactor: 1.5); 
            } 
          )
      )
    )
  );
}

class Landing extends StatelessWidget {
  Landing({Key key}) : super(key: key);

  Widget build(BuildContext cntxt) => Scaffold(
    body: Center(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text("Store", textScaleFactor: 8),
          RaisedButton(
            child: Text("Ordina", textScaleFactor: 1.5),
            onPressed: ()=>Navigator.push(cntxt, CupertinoPageRoute(builder: (cntxt)=>Mainpage())),
          )
        ],
      )
    )
  );
}

class Mainpage extends StatefulWidget{
  Mainpage({Key key}): super(key: key);

  @override
  MainpageState createState() => MainpageState();
}

class MainpageState extends State<Mainpage> {
  StreamController<Item> controller = StreamController.broadcast();

  @override
  void dispose(){
    controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext cntxt) => Scaffold(
    appBar: AppBar(
      title: Text('Ordina', textScaleFactor: 1.8),
      centerTitle: true
    ),
    body: Overlay(
      initialEntries: [
        OverlayEntry(
          maintainState: true,
          builder: (cntxt)=>CustomMultiChildLayout(
            delegate: HorizontallySplitView(),
            children: <Widget>[
              LayoutId(
                id: 'left',
                child: Store(controller.sink)
              ),
              LayoutId(
                id: 'right',
                child: Cart(controller.stream)
              )
            ]
          )
        )
      ]
    )
  );
}

class Store extends StatelessWidget {
  Store(this._sink, {Key key}) : super(key: key);

  OverlayEntry _currentEntry;
  final StreamSink<Item> _sink;

  void _removeOverlay(){
    _currentEntry.remove();
    _currentEntry = null;
  }

  List<Widget> _buildCategory(String kind) => [
    SliverAppBar(
      title: Text(kind),
      centerTitle: true,
      automaticallyImplyLeading: false,
    ),
    SliverGrid(
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200
      ),
      delegate: SliverChildBuilderDelegate(
        (cntxt, idx){
          Product current = prodotti[kind][idx];
          return SizedBox.expand(
            child: Card(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)
              ),
              elevation: 2,
              child: FlatButton(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if(current.imagePath != null)
                        ...[
                          Padding(
                            padding: EdgeInsets.only(bottom: 5),
                            child: Image.network(
                              'http://${window.location.host}/img/${current.imagePath}',
                              height: 120,
                            )
                          ),
                          Spacer()
                        ],
                      Text('${current.name} - ${current.stringPrice}€', style: TextStyle(color: Colors.black))
                    ]
                  )
                ),
                onPressed: current.variations != null ?
                  (){
                  _currentEntry = OverlayEntry(
                    builder: (cntxt)=>MealDialog(
                      current.variations,
                      onCancellation: _removeOverlay,
                      onApproval: (choices){
                        _sink.add(
                          Item(
                            current,
                            choices,
                            1
                          )
                        );
                        _removeOverlay();
                      },
                    )
                  );
                  Overlay.of(cntxt).insert(_currentEntry);
                } 
                : ()=>_sink.add(
                    Item(
                      current,
                      null,
                      1
                    )
                  )
              )
            )
          );
        },
        childCount: prodotti[kind].length
      )
    )
  ];

  @override
  Widget build(BuildContext cntxt)=>Container(
    decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey))),
    child: Scaffold(
      body: CustomScrollView(
        slivers: [
          for (String k in prodotti.keys)
            ..._buildCategory(k)
        ]
      ) 
    )
  );
}

class MealDialog extends StatelessWidget {
  MealDialog(this._variations, {this.onCancellation, this.onApproval, Key key}):super(key: key);

  final VoidCallback onCancellation;
  final void Function(Map<String, dynamic>) onApproval;
  final Map<String, VariationList> _variations;
  final Map<String, dynamic> _choices = {};

  Widget _buildSection(String name){
    VariationList l = _variations[name];
    _choices[name] = l.listKind == ListKind.Check ? List<String>() : ''; 
    return StatefulBuilder(
      builder: (cntxt, setState)=>Column(
        children: l.listKind == ListKind.Check ?
          [
            for(String key in l.variations)
              CheckboxListTile(
                controlAffinity: ListTileControlAffinity.leading,
                value: _choices[name].contains(key),
                onChanged: (selected)=>setState(
                  ()=>selected ?
                    _choices[name].add(key)
                    : _choices[name].remove(key)
                ),
                title: Text(key),
              )
        ]
        :[
          for(String key in l.variations)
            RadioListTile<String>(
              value: key,
              onChanged: (value)=>setState(
                ()=>_choices[name] = value
              ),
              groupValue: _choices[name],
              title: Text(key)
            )
        ],
      )
    );
  }

  Widget build(BuildContext cntxt) => Material(
    color: Colors.grey.withAlpha(128),
    child: CustomSingleChildLayout(
      delegate: MealDelegate(),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: CustomMultiChildLayout(
          delegate: MealBodyDelegate(),
          children: <Widget>[
            LayoutId(
              id: 'list',
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  for(String key in _variations.keys)
                    ...[
                      Text(key, style: TextStyle(fontWeight: FontWeight.w600)),
                      _buildSection(key)
                    ],
                ]
              )
            ),
            LayoutId(
              id: 'btns',
              child: ButtonBar(
                children: <Widget>[
                  FlatButton(
                    child: Text('Annulla'),
                    onPressed: onCancellation,
                  ),
                  RaisedButton(
                    child: Text('Aggiungi al Carrello'),
                    color: Colors.red,
                    onPressed: ()=>onApproval(_choices),
                  )
                ],
              )
            )
          ]
        )
      )
    )
  );
}

class Cart extends StatefulWidget {
  Cart(this.events, {Key key}) : assert(events != null), super(key: key);
  final Stream<Item> events;

  CartState createState()=>CartState();
}

class CartState extends State<Cart> {
  List<Item> order = List();
  StreamSubscription<Item> sub;

  @override
  void initState(){
    super.initState();
    sub = widget.events.listen(
      (i){
        if(!order.contains(i)) 
          setState(()=>order.add(i));
      }
    );
  }

  @override
  void dispose(){
    sub?.cancel();
    super.dispose();
  }

  List<Widget> _buildChoices(dynamic choice){
    if(choice is List<String>) return [
      for(String value in choice)
        Text('-$value')
    ];
    else return [
      Text('-$choice')
    ];
  }

  Widget build(BuildContext cntxt) => Container(
    decoration: BoxDecoration(border: Border(left: BorderSide(color: Colors.grey))),
    child: Scaffold(
      body: ListView.builder(
        itemCount: order.length+1,
        itemBuilder: (cntxt, idx){
          if(idx >= order.length) return ListTile(
            leading: Text('Totale'),
            trailing: Text('${prettyPrintPrice(intTotal(order))}€'),
          );
          else {
            Item current = order.elementAt(idx);
            return Card(
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                    child: Container(
                      decoration: current.chosvar != null ? BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.grey,
                            width: 1.3
                          )
                        )
                      )
                      : null,
                      child: ListTile(
                        leading: Text('${current.product.name}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Padding(
                              padding: EdgeInsets.only(right: 15),
                              child: NumPicker(
                                currentNumber: current.quantity,
                                onChange: (val)=>setState(()=>current.quantity=val),
                              ),
                            ),
                            RaisedButton(
                              child: Icon(Icons.close),
                              onPressed: ()=>setState(()=>order.remove(current)),
                              color: Colors.red,
                            )
                          ],
                        )
                      )
                    )
                  ),
                  current.chosvar != null ? Padding(
                    padding: EdgeInsets.symmetric(vertical: 7, horizontal: 10),
                    child: DefaultTextStyle(
                      style: TextStyle(
                        color: Colors.grey
                      ),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Column(
                          children: <Widget>[
                            for(String key in current.chosvar.keys)
                              ...[
                                Text("$key:"),
                                ..._buildChoices(current.chosvar[key])
                              ]
                          ]
                        ),
                      )
                    )
                  )
                  : Container()
                ]
              )
            );
          }
        }
      ),
      floatingActionButton: order.length > 0 ?
        FloatingActionButton(
          child: Icon(Icons.shopping_cart),
          onPressed: (){
            try {
              List<int> unenc = List.from(utf8.encode(json.encode(order)));
              List<Uint8List> body = [];
              while(unenc.length > 0){
                int blockLen = min(rsa.inputBlockSize, unenc.length);
              
                Uint8List block = Uint8List.fromList(unenc.sublist(0, blockLen));
                unenc.removeRange(0, blockLen);
                body.add(rsa.process(block));
              }

              httpClient.post(
                Uri.http(
                  window.location.host,
                  'print',
                  { "p": idxPrinter.toString() }
                ),
                body: json.encode(body)
              );
            } on Exception catch(e) {
              print(e.toString());
            }
            Navigator.popUntil(cntxt, (route)=>route.isFirst);
          }
        ) : null,
    )
  );
}

class NumPicker extends StatelessWidget {
  NumPicker(
    {
      Key key,
      this.mainAxisSize,
      this.currentNumber = 0,
      this.onChange
    }
  ): super(key: key);

  final MainAxisSize mainAxisSize;
  final void Function(int) onChange;
  int currentNumber = 0;

  Widget build(BuildContext cntxt) => StatefulBuilder(
    builder: (cntxt, setState)=>Row(
      mainAxisSize: mainAxisSize ?? MainAxisSize.max,
      children: <Widget>[
        SizedBox(
          width: 50,
          child: FlatButton(
            child: Icon(Icons.arrow_left),
            onPressed: currentNumber == 0 ? null : (){
              setState(()=>--currentNumber);
              onChange(currentNumber);
            }
          )
        ),
        Text(currentNumber.toString()),
        SizedBox(
          width: 50,
          child: FlatButton(
            child: Icon(Icons.arrow_right),
            onPressed: (){
              setState(()=>++currentNumber);
              onChange(currentNumber);
            }
          )
        )
      ]
    )
  );
}
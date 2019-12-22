import 'product.dart';
import 'dart:io';
import 'dart:convert' show json;

void main() async {
  await File('product.json').writeAsString(
    json.encode(
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
      }
    )
  );
}
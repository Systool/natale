import 'package:flutter/material.dart';

class MealDelegate extends SingleChildLayoutDelegate {
  MealDelegate({Listenable relayout}): super(relayout: relayout);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints cons) => BoxConstraints.loose(
    Size(
      cons.maxWidth < 1000 ? cons.maxWidth-2: 1000,
      cons.maxHeight-2
    )
  );

  Offset getPositionForChild(Size size, Size childSize)=>Offset(
    size.width/2-childSize.width/2,
    size.height/2-childSize.height/2
  );

  bool shouldRelayout(MealDelegate old)=>false;
}

class HorizontallySplitView extends MultiChildLayoutDelegate {
  HorizontallySplitView({Listenable relayout}): super(relayout: relayout);

  void performLayout(Size size){
    double lWidth = layoutChild(
      'left',
      BoxConstraints.tightFor(
        width: size.width/2,
        height: size.height
      )
    ).width;
    positionChild('left', Offset(0, 0));
    layoutChild(
      'right',
      BoxConstraints.tightFor(
        width: size.width-lWidth,
        height: size.height
      )
    );
    positionChild('right', Offset(lWidth, 0));
  }

  bool shouldRelayout(HorizontallySplitView old) => false; 
}
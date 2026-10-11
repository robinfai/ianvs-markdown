import 'dart:ffi';

final class Rect extends Struct {
  @Double()
  external double x;
}

Pointer<Rect> position(Pointer<Rect> rect) => rect;
void main() {
  if (<int>[1].length > 1) {
    final callback =
        NativeCallable<Pointer<Rect> Function(Pointer<Rect>)>.isolateLocal(
          position,
        );
    callback.close();
  }
}

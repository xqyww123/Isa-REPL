ML-MessagePack
==============

MessagePack implementation for Standard ML (SML)

Features
--------

- Portable: Depends only on the required components of the SML Basis Library specification.
- Composable: Composable combinators for encoding and decoding.

Usage
-----

#### MLton and MLKit

Include mlmsgpack.mlb in your MLB file.

#### Poly/ML

From the interactive shell, use .sml files in the following order.

- mlmsgpack-aux.sml
- realprinter-default.sml
- mlmsgpack.sml

#### SML/NJ

Use mlmsgpack.cm.

#### Moscow ML

From the interactive shell, use .sml files in the following order.

- large.sml
- mlmsgpack-aux.sml
- realprinter-fail.sml
- mlmsgpack.sml

Makefile.mosml is also provided.

#### HaMLet

From the interactive shell, use .sml files in the following order.

- mlmsgpack-aux.sml
- realprinter-fail.sml
- mlmsgpack.sml

#### Alice ML

Makefile.alice is provided.

```
make -f Makefile.alice
alicerun mlmsgpack-test
```

#### SML# ####

For separate compilation, .smi files are provided. Require mlmsgpack.smi from your .smi file.

From the interactive shell, use .sml files in the following order.

- mlmsgpack-aux.sml
- realprinter-default.sml
- mlmsgpack.sml

Tutorial
--------

See TUTORIAL.md.

Known Problems
--------------

Our recommendation is MLton, MLKit, Poly/ML and SML#(>=2.0.0) as all tests passed on them.
SML/NJ and Moscow ML are fine if you don't use real values.

#### SML/NJ

Packing real values fail or produces imprecise results in some cases.

#### Moscow ML

Packing real values is not supported, since some components of the SML Basis Library are not provided.

#### HaMLet

Packing real values is not supported, since some components of the SML Basis Library are not provided.
Some functions are very slow, although they work properly. (We tested HaMLet compiled with MLton.)

#### Alice ML

Packing real values is not supported, since some components of the SML Basis Library are not provided.
Also, some unit tests fail.

#### SML# ####

Most functions do not work properly because of bugs of SML# prior to version 2.0.0.

See Also
--------

There already exists another MessagePack implemenatation for SML, 
called MsgPack-SML, which is targeted for MLton.

https://msgpacksml.codeplex.com/

ML-MessagePack is written from scratch and not a fork of MsgPack-SML.

For information on MessagePack, see:

http://msgpack.org/

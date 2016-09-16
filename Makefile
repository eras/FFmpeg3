OCAMLBUILD = ocamlbuild

all:
	$(OCAMLBUILD) -j 4 make.otarget

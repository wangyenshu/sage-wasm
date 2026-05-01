#!/usr/bin/env bash
set -eux

BASEDIR="$(pwd)"

if ! command -v emmake &> /dev/null; then
    echo "Error: Please install and source Emscripten 3.1.23."
    echo "See https://emscripten.org/docs/getting_started/downloads.html"
    exit 1
fi

AUX_BUILD="$BASEDIR/emscripten/build"
AUX_PREFIX="$BASEDIR/emscripten/install"
EXTERN_DIR="$BASEDIR/emscripten/extern"

mkdir -p "$AUX_BUILD"
mkdir -p "$AUX_PREFIX"
mkdir -p "$EXTERN_DIR"

# Generate autotools scripts if missing
if [[ ! -f ./configure ]]; then
    echo "Bootstrapping SageMath configure script..."
    make configure
fi

# EXTERNAL LIBRARIES
# --- GMP ---
(
    mkdir -p "$AUX_BUILD/gmp"
    cd "$AUX_BUILD/gmp"
    if [[ ! -d "$EXTERN_DIR/gmp" ]]; then
        echo "Downloading GMP source..."
        hg clone https://gmplib.org/repo/gmp/ "$EXTERN_DIR/gmp"
        cd "$EXTERN_DIR/gmp" && ./.bootstrap && cd -
    fi
    if [[ ! -f config.status ]]; then
        CC_FOR_BUILD=/usr/bin/gcc ABI=standard \
        emconfigure "$EXTERN_DIR/gmp/configure" \
            --build i686-pc-linux-gnu --host none \
            --disable-assembly --enable-cxx \
            --prefix="$AUX_PREFIX"
    fi
    emmake make -j8
    emmake make install
)

# --- MPFR ---
(
    mkdir -p "$AUX_BUILD/mpfr"
    cd "$AUX_BUILD/mpfr"
    if [[ ! -d "$EXTERN_DIR/mpfr" ]]; then
        echo "Downloading MPFR source..."
        git clone https://gitlab.inria.fr/mpfr/mpfr.git "$EXTERN_DIR/mpfr"
        cd "$EXTERN_DIR/mpfr" && ./autogen.sh && cd -
    fi
    if [[ ! -f config.status ]]; then
        emconfigure "$EXTERN_DIR/mpfr/configure" \
            --build i686-pc-linux-gnu --host none \
            --with-gmp="$AUX_PREFIX" \
            --disable-shared \
            --prefix="$AUX_PREFIX"
    fi
    emmake make -j8
    emmake make install
)

# --- FLINT ---
(
    mkdir -p "$AUX_BUILD/flint"
    cd "$AUX_BUILD/flint"
    if [[ ! -d "$EXTERN_DIR/flint2" ]]; then
        echo "Cloning Flint..."
        git clone --depth 1 https://github.com/wbhart/flint2.git "$EXTERN_DIR/flint2"
        cd "$EXTERN_DIR/flint2" && ./bootstrap.sh && cd -
    fi
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/flint2/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --with-gmp="$AUX_PREFIX" \
            --with-mpfr="$AUX_PREFIX" \
            --disable-shared \
            --disable-assembly \
            --prefix="$AUX_PREFIX"
    fi
    emmake make -j8
    emmake make install
)

# --- NTL ---
(
    mkdir -p "$AUX_BUILD/ntl"
    cd "$AUX_BUILD/ntl"
    
    if [[ ! -d "$EXTERN_DIR/ntl" ]]; then
        echo "Cloning NTL..."
        git clone https://github.com/libntl/ntl.git "$EXTERN_DIR/ntl"
    fi
    cd "$EXTERN_DIR/ntl/src"
    
    if [[ ! -f makefile ]]; then
        emconfigure ./configure \
            CXX="em++" \
            CXXFLAGS="-O2 -fexceptions -s WASM=1 -s NODERAWFS=1" \
            PREFIX="$AUX_PREFIX" \
            GMP_PREFIX="$AUX_PREFIX" \
            NTL_GMP_LIP=on \
            NTL_STD_CXX14=on \
            SHARED=off \
            NATIVE=off \
            TUNE=generic \
            NTL_THREADS=off

        sed -e 's/^CC=gcc/CC=emcc -s NODERAWFS=1/' \
            -e 's/^WIZARD=on/WIZARD=off/' \
            makefile > makefile.patched
        mv makefile.patched makefile
    fi
    
    if ! emmake make -j8; then
        
        sed -e 's|^\t\./MakeDesc|\tchmod +x ./MakeDesc \&\& node ./MakeDesc|' \
            -e 's|^\t\./gen_gmp_aux|\tchmod +x ./gen_gmp_aux \&\& node ./gen_gmp_aux|' \
            -e 's|^\t\./gen_lip_gmp_aux|\tchmod +x ./gen_lip_gmp_aux \&\& node ./gen_lip_gmp_aux|' \
            -e 's|^\t\./gen_lip_gmp_aux|\tchmod +x ./gen_lip_gmp_aux \&\& node ./gen_lip_gmp_aux|' \
            makefile > makefile.patched
        mv makefile.patched makefile
        
        sed -i 's|if ./CheckFeatures|if node ./CheckFeatures|g' MakeCheckFeatures
        
        if [ -f MakeCheckThreads ]; then
            sed -i 's|./CheckThreads|node ./CheckThreads|g' MakeCheckThreads
        fi
        
        emmake make -j8
    fi

    emmake make install
    emranlib "$AUX_PREFIX/lib/libntl.a"
)

# --- CDDLIB ---
(
    if [[ ! -d "$EXTERN_DIR/cddlib" ]]; then
        echo "Cloning cddlib..."
        git clone https://github.com/cddlib/cddlib.git "$EXTERN_DIR/cddlib"
    fi

    cd "$EXTERN_DIR/cddlib"
    
    if [[ ! -f configure ]]; then
        ./bootstrap
    fi

    if [[ ! -f Makefile ]]; then
        CPPFLAGS="-I$AUX_PREFIX/include" \
        LDFLAGS="-L$AUX_PREFIX/lib" \
        CFLAGS="-O2" \
        CXXFLAGS="-O2" \
        emconfigure ./configure \
            --with-gmp="$AUX_PREFIX" \
            --disable-shared \
            --prefix="$AUX_PREFIX"
    fi
    
    emmake make -j8
    emmake make install

    cd "$AUX_PREFIX/include"
    ln -sf cddlib/*.h .
    ln -sf cddmp.h cdd_mp.h
)

# --- LIBATOMIC_OPS ---
(
    mkdir -p "$AUX_BUILD/libatomic_ops"
    cd "$AUX_BUILD/libatomic_ops"
    
    if [[ ! -d "$EXTERN_DIR/libatomic_ops" ]]; then
        echo "Cloning libatomic_ops..."
        git clone https://github.com/bdwgc/libatomic_ops.git "$EXTERN_DIR/libatomic_ops"
        cd "$EXTERN_DIR/libatomic_ops" && ./autogen.sh && cd -
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/libatomic_ops/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --disable-shared \
            --prefix="$AUX_PREFIX"
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBBOOST ---
# --- LIBBRAIDING ---
(
    mkdir -p "$AUX_BUILD/libbraiding"
    cd "$AUX_BUILD/libbraiding"
    
    if [[ ! -d "$EXTERN_DIR/libbraiding" ]]; then
        echo "Cloning libbraiding..."
        git clone https://github.com/miguelmarco/libbraiding.git "$EXTERN_DIR/libbraiding"
        cd "$EXTERN_DIR/libbraiding" && autoreconf -vfi && cd -
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/libbraiding/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --disable-shared \
            --prefix="$AUX_PREFIX"
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBBRIAL ---
(
    mkdir -p "$AUX_BUILD/libbrial"
    cd "$AUX_BUILD/libbrial"
    
    if [[ ! -d "$EXTERN_DIR/libbrial" ]]; then
        echo "Cloning libBRiAl..."
        git clone https://github.com/BRiAl/libBRiAl.git "$EXTERN_DIR/libbrial"
        cd "$EXTERN_DIR/libbrial" && autoreconf -vfi && cd -
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/libbrial/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --disable-shared \
            --prefix="$AUX_PREFIX"
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBBZ2 ---
(
    if [[ ! -d "$EXTERN_DIR/bzip2" ]]; then
        echo "Cloning bzip2..."
        git clone git://sourceware.org/git/bzip2.git "$EXTERN_DIR/bzip2"
    fi

    cd "$EXTERN_DIR/bzip2"
    
    if [[ ! -f libbz2.a ]]; then
        emmake make libbz2.a \
            CC="emcc" \
            AR="emar" \
            RANLIB="emranlib" \
            CFLAGS="-D_FILE_OFFSET_BITS=64 $CFLAGS" \
            -j8
    fi
    
    echo "Installing bzip2..."
    mkdir -p "$AUX_PREFIX/include" "$AUX_PREFIX/lib"
    cp bzlib.h "$AUX_PREFIX/include/"
    cp libbz2.a "$AUX_PREFIX/lib/"
)
# --- LIBCLIQUER ---
(
    mkdir -p "$AUX_BUILD/cliquer"
    cd "$AUX_BUILD/cliquer"
    
    if [[ ! -d "$EXTERN_DIR/cliquer-1.21" ]]; then
        echo "Downloading Cliquer..."
        curl -sSL http://users.aalto.fi/~pat/cliquer/cliquer-1.21.tar.gz | tar xz -C "$EXTERN_DIR"
    fi
    
    cd "$EXTERN_DIR/cliquer-1.21"
    
    if [[ ! -f libcliquer.a ]]; then
        echo "Building libcliquer.a..."
        emcc $CFLAGS -c cliquer.c graph.c reorder.c
        emar rc libcliquer.a cliquer.o graph.o reorder.o
        emranlib libcliquer.a
    fi
    
    echo "Installing Cliquer..."
    mkdir -p "$AUX_PREFIX/include/cliquer" "$AUX_PREFIX/lib"
    cp *.h "$AUX_PREFIX/include/cliquer/"
    cp libcliquer.a "$AUX_PREFIX/lib/"
)
# --- LIBECL ---
# --- LIBECM ---
(
    mkdir -p "$AUX_BUILD/ecm"
    cd "$AUX_BUILD/ecm"
    
    if [[ ! -d "$EXTERN_DIR/ecm" ]]; then
        echo "Cloning ecm..."
        git clone https://gitlab.inria.fr/zimmerma/ecm.git "$EXTERN_DIR/ecm"
        
        cd "$EXTERN_DIR/ecm" && autoreconf -i && cd -
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/ecm/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --with-gmp="$AUX_PREFIX" \
            --disable-shared \
            --prefix="$AUX_PREFIX"
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBFFI ---
(
    mkdir -p "$AUX_BUILD/libffi"
    cd "$AUX_BUILD/libffi"
    
    if [[ ! -d "$EXTERN_DIR/libffi" ]]; then
        echo "Cloning libffi..."
        git clone https://github.com/libffi/libffi.git "$EXTERN_DIR/libffi"
        
        cd "$EXTERN_DIR/libffi" && ./autogen.sh && cd -
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/libffi/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --disable-shared \
            --disable-docs \
            --prefix="$AUX_PREFIX"
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBFFLAS_FFPACK ---
# --- LIBFPLLL ---
(
    mkdir -p "$AUX_BUILD/fplll"
    cd "$AUX_BUILD/fplll"
    
    if [[ ! -d "$EXTERN_DIR/fplll" ]]; then
        echo "Cloning fplll..."
        git clone https://github.com/fplll/fplll.git "$EXTERN_DIR/fplll"
        
        cd "$EXTERN_DIR/fplll" && ./autogen.sh && cd -
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/fplll/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --with-gmp="$AUX_PREFIX" \
            --with-mpfr="$AUX_PREFIX" \
            --disable-shared \
            --prefix="$AUX_PREFIX"
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBFREETYPE ---
(
    mkdir -p "$AUX_BUILD/freetype"
    cd "$AUX_BUILD/freetype"
    
    if [[ ! -d "$EXTERN_DIR/freetype" ]]; then
        echo "Cloning FreeType..."
        git clone https://gitlab.freedesktop.org/freetype/freetype.git "$EXTERN_DIR/freetype"
        
        cd "$EXTERN_DIR/freetype" && sh autogen.sh && cd -
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/freetype/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --disable-shared \
            --prefix="$AUX_PREFIX"
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBGAP ---
# --- LIBGC ---
(
    mkdir -p "$AUX_BUILD/bdwgc"
    cd "$AUX_BUILD/bdwgc"
    
    if [[ ! -d "$EXTERN_DIR/bdwgc" ]]; then
        echo "Cloning Boehm GC..."
        git clone https://github.com/bdwgc/bdwgc.git "$EXTERN_DIR/bdwgc"
        
        cd "$EXTERN_DIR/bdwgc" && ./autogen.sh && cd -
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/bdwgc/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --disable-shared \
            --disable-threads \
            --enable-cplusplus \
            --prefix="$AUX_PREFIX"
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBGD ---
(
    mkdir -p "$AUX_BUILD/gd"
    cd "$AUX_BUILD/gd"
    
    if [[ ! -d "$EXTERN_DIR/gd" ]]; then
        echo "Cloning libgd..."
        git clone https://github.com/libgd/libgd.git "$EXTERN_DIR/gd"
        
        cd "$EXTERN_DIR/gd" && ./bootstrap.sh && cd -
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/gd/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --disable-shared \
            --disable-werror \
            --without-x \
            --without-xpm \
            --prefix="$AUX_PREFIX"
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBGF2X ---
(
    mkdir -p "$AUX_BUILD/gf2x"
    cd "$AUX_BUILD/gf2x"
    
    if [[ ! -d "$EXTERN_DIR/gf2x" ]]; then
        echo "Cloning gf2x..."
        git clone https://gitlab.inria.fr/gf2x/gf2x.git "$EXTERN_DIR/gf2x"
        
        cd "$EXTERN_DIR/gf2x" && autoreconf -vfi && cd -
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/gf2x/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --disable-shared \
            --prefix="$AUX_PREFIX" \
            ABI=32
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBGFAN ---
(
    mkdir -p "$AUX_BUILD/gfanlib"
    cd "$AUX_BUILD/gfanlib"
    
    if [[ ! -d "$EXTERN_DIR/gfanlib0.6.2" ]]; then
        echo "Downloading gfanlib..."
        curl -sSL https://users-math.au.dk/jensen/software/gfan/gfanlib0.6.2.tar.gz | tar xz -C "$EXTERN_DIR"
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/gfanlib0.6.2/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --prefix="$AUX_PREFIX" \
            CPPFLAGS="-I$AUX_PREFIX/include -I$AUX_PREFIX/include/cddlib" \
            LDFLAGS="-L$AUX_PREFIX/lib" \
            CXXFLAGS="$CXXFLAGS"
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBGIVARO ---
(
    mkdir -p "$AUX_BUILD/givaro"
    cd "$AUX_BUILD/givaro"
    
    if [[ ! -d "$EXTERN_DIR/givaro" ]]; then
        echo "Cloning givaro..."
        git clone https://github.com/linbox-team/givaro.git "$EXTERN_DIR/givaro"
        
        cd "$EXTERN_DIR/givaro" && ./autogen.sh && cd -
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/givaro/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --with-gmp="$AUX_PREFIX" \
            --disable-shared \
            --prefix="$AUX_PREFIX" \
            CFLAGS="$CFLAGS" \
            CXXFLAGS="$CXXFLAGS"
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBGLPK ---
(
    mkdir -p "$AUX_BUILD/glpk"
    cd "$AUX_BUILD/glpk"
    
    if [[ ! -d "$EXTERN_DIR/glpk-5.0" ]]; then
        echo "Downloading glpk..."
        curl -sSL https://ftp.gnu.org/gnu/glpk/glpk-5.0.tar.gz | tar xz -C "$EXTERN_DIR"
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/glpk-5.0/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --with-gmp \
            --disable-shared \
            --prefix="$AUX_PREFIX" \
            CPPFLAGS="-I$AUX_PREFIX/include" \
            LDFLAGS="-L$AUX_PREFIX/lib"
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBGSL ---
(
    mkdir -p "$AUX_BUILD/gsl"
    cd "$AUX_BUILD/gsl"
    
    if [[ ! -d "$EXTERN_DIR/gsl-2.8" ]]; then
        echo "Downloading GSL..."
        curl -sSL https://ftp.gnu.org/gnu/gsl/gsl-2.8.tar.gz | tar xz -C "$EXTERN_DIR"
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/gsl-2.8/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --disable-shared \
            --prefix="$AUX_PREFIX" \
            CFLAGS="$CFLAGS" \
            LDFLAGS="$LDFLAGS"
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBHOMFLY ---
(
    mkdir -p "$AUX_BUILD/libhomfly"
    cd "$AUX_BUILD/libhomfly"
    
    if [[ ! -d "$EXTERN_DIR/libhomfly" ]]; then
        echo "Cloning libhomfly..."
        git clone https://github.com/miguelmarco/libhomfly.git "$EXTERN_DIR/libhomfly"
        
        cd "$EXTERN_DIR/libhomfly" && autoreconf -vfi && cd -
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/libhomfly/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --disable-shared \
            --prefix="$AUX_PREFIX" \
            CFLAGS="$CFLAGS"
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBIML ---
(
    mkdir -p "$AUX_BUILD/iml"
    cd "$AUX_BUILD/iml"
    
    if [[ ! -d "$EXTERN_DIR/iml-1.0.5" ]]; then
        echo "Downloading iml..."
        curl -sSL http://www.cs.uwaterloo.ca/~astorjoh/iml-1.0.5.tar.bz2 | tar xj -C "$EXTERN_DIR"
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/iml-1.0.5/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --with-gmp="$AUX_PREFIX" \
            --disable-shared \
            --prefix="$AUX_PREFIX" \
            CFLAGS="$CFLAGS" \
            LDFLAGS="$LDFLAGS"
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBLFUNCTION (lcalc) ---
(
    mkdir -p "$AUX_BUILD/lcalc"
    cd "$AUX_BUILD/lcalc"
    
    if [[ ! -d "$EXTERN_DIR/lcalc" ]]; then
        echo "Downloading lcalc..."
        mkdir -p "$EXTERN_DIR/lcalc"
        curl -sSL https://storage.googleapis.com/google-code-archive-source/v2/code.google.com/l-calc/source-archive.zip -o lcalc.zip
        
        unzip -q lcalc.zip -d "$EXTERN_DIR/lcalc_temp"
        SRC_DIR=$(dirname "$(find "$EXTERN_DIR/lcalc_temp" -name "Makefile" | head -n 1)")
        mv "$SRC_DIR"/* "$EXTERN_DIR/lcalc/"
        rm -rf lcalc.zip "$EXTERN_DIR/lcalc_temp"
    fi
    
    cd "$EXTERN_DIR/lcalc"
    
    if [[ ! -f libLfunction.a ]]; then
        sed -i.bak -e "s|/usr/local|$AUX_PREFIX|g" Makefile
        
        emmake make lib \
            CC="emcc" \
            CXX="em++" \
            AR="emar" \
            CXXFLAGS="$CXXFLAGS" \
            LDFLAGS="$LDFLAGS" \
            -j8
    fi
    
    emmake make install
)
# --- LIBLINBOX ---
(
    mkdir -p "$AUX_BUILD/linbox"
    cd "$AUX_BUILD/linbox"
    
    if [[ ! -d "$EXTERN_DIR/linbox" ]]; then
        echo "Cloning linbox..."
        git clone https://github.com/linbox-team/linbox.git "$EXTERN_DIR/linbox"
        
        cd "$EXTERN_DIR/linbox" && ./autogen.sh && cd -
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/linbox/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --with-gmp="$AUX_PREFIX" \
            --with-givaro="$AUX_PREFIX" \
            --with-fflas-ffpack="$AUX_PREFIX" \
            --disable-shared \
            --prefix="$AUX_PREFIX" \
            CFLAGS="$CFLAGS" \
            CXXFLAGS="$CXXFLAGS"
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBLRCALC ---
(
    mkdir -p "$AUX_BUILD/lrcalc"
    cd "$AUX_BUILD/lrcalc"
    
    if [[ ! -d "$EXTERN_DIR/lrcalc" ]]; then
        echo "Cloning lrcalc..."
        git clone https://bitbucket.org/asbuch/lrcalc.git "$EXTERN_DIR/lrcalc"
        
        cd "$EXTERN_DIR/lrcalc" && autoreconf -vfi && cd -
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/lrcalc/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --disable-shared \
            --prefix="$AUX_PREFIX" \
            CFLAGS="$CFLAGS" \
            CXXFLAGS="$CXXFLAGS"
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBLZMA ---
(
    mkdir -p "$AUX_BUILD/xz"
    cd "$AUX_BUILD/xz"
    
    if [[ ! -d "$EXTERN_DIR/xz" ]]; then
        echo "Cloning xz (liblzma)..."
        git clone https://github.com/tukaani-project/xz.git "$EXTERN_DIR/xz"
        
        cd "$EXTERN_DIR/xz"
        if [[ ! -f configure ]]; then
            ./autogen.sh
        fi
        cd -
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/xz/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --disable-shared \
            --disable-assembler \
            --disable-threads \
            --disable-xz \
            --disable-xzdec \
            --disable-lzmadec \
            --disable-lzmainfo \
            --disable-scripts \
            --disable-doc \
            --prefix="$AUX_PREFIX" \
            CFLAGS="$CFLAGS" \
            CXXFLAGS="$CXXFLAGS"
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBM4RI ---
(
    mkdir -p "$AUX_BUILD/m4ri"
    cd "$AUX_BUILD/m4ri"
    
    if [[ ! -d "$EXTERN_DIR/m4ri" ]]; then
        echo "Cloning m4ri..."
        git clone https://github.com/malb/m4ri.git "$EXTERN_DIR/m4ri"
        
        cd "$EXTERN_DIR/m4ri"
        if [[ ! -f configure ]]; then
            autoreconf --install
        fi
        cd -
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/m4ri/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --disable-shared \
            --disable-openmp \
            --prefix="$AUX_PREFIX" \
            CFLAGS="$CFLAGS" \
            CXXFLAGS="$CXXFLAGS"
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBM4RIE ---
(
    mkdir -p "$AUX_BUILD/m4rie"
    cd "$AUX_BUILD/m4rie"
    
    if [[ ! -d "$EXTERN_DIR/m4rie" ]]; then
        echo "Cloning m4rie..."
        git clone https://github.com/malb/m4rie.git "$EXTERN_DIR/m4rie"
        
        cd "$EXTERN_DIR/m4rie"
        if [[ ! -f configure ]]; then
            if [[ -f autogen.sh ]]; then
                ./autogen.sh
            else
                autoreconf --install
            fi
        fi
        cd -
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/m4rie/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --disable-shared \
            --prefix="$AUX_PREFIX" \
            CFLAGS="$CFLAGS" \
            CXXFLAGS="$CXXFLAGS" \
            LDFLAGS="$LDFLAGS"
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBMPC ---
# --- LIBMPFI ---
# --- LIBNAUTY ---
# --- LIBNCURSES ---
# --- LIBOPENBLAS ---
# --- LIBOPENSSL ---
# --- LIBPARI ---
# --- LIBPLANARITY ---
# --- LIBPPL ---
# --- LIBPRIMECOUNT ---
# --- LIBPRIMESIEVE ---
# --- LIBPYTHON3 ---
# --- LIBQHULL ---
# --- LIBREADLINE ---
# --- LIBRW ---
# --- LIBSINGULAR ---
# --- LIBSQLITE3 ---
# --- LIBSUITESPARSE ---
# --- LIBSYMMETRICA ---
# --- LIBZ ---
# --- LIBZMQ ---

# ==========================================

export EMCC_CFLAGS="-fexceptions"

export CFLAGS="-O2 -fexceptions -s WASM=1 -I$AUX_PREFIX/include"
export CXXFLAGS="-O2 -fexceptions -s WASM=1 -std=c++14 -I$AUX_PREFIX/include"
export LDFLAGS="-L$AUX_PREFIX/lib -fexceptions -s ASYNCIFY=1 -s ALLOW_MEMORY_GROWTH=1 -s ERROR_ON_UNDEFINED_SYMBOLS=1"

echo "Configuring SageMath for wasm32-unknown-emscripten..."
emconfigure ./configure \
    --build=i686-pc-linux-gnu \
    --host=wasm32-unknown-emscripten \
    --prefix="$AUX_PREFIX" \
    --disable-shared \
    --enable-static \
    --without-system-python3 \
    --enable-gmp \
    --enable-mpfr \
    --enable-flint \
    --enable-gsl \
    CC="emcc -fexceptions" \
    CXX="em++ -fexceptions" \
    AR="emar" \
    RANLIB="emranlib"

echo "Building SageMath modules..."
emmake make -j8

echo "SageMath Wasm build complete."
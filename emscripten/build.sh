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
(
    BOOST_VERSION_DIR="boost_1_91_0"
    BOOST_VERSION_URL="1.91.0"
    mkdir -p "$AUX_BUILD/boost"
    cd "$AUX_BUILD/boost"
    
    if [[ ! -d "$EXTERN_DIR/$BOOST_VERSION_DIR" ]]; then
        echo "Downloading Boost $BOOST_VERSION_URL..."
        curl -sSL "https://archives.boost.io/release/$BOOST_VERSION_URL/source/${BOOST_VERSION_DIR}.tar.gz" | tar xz -C "$EXTERN_DIR"
    fi
    
    cd "$EXTERN_DIR/$BOOST_VERSION_DIR"
    
    if [[ ! -f b2 ]]; then
        env -u CC -u CXX -u CFLAGS -u CXXFLAGS -u LDFLAGS \
        ./bootstrap.sh --with-toolset=gcc
    fi
    
    cat > user-config-wasm.jam <<EOF
using emscripten : : em++ : 
    <cxxflags>"$CXXFLAGS" 
    <cflags>"$CFLAGS" 
    <linkflags>"$LDFLAGS" 
    <archiver>emar 
    <ranlib>emranlib 
;
EOF

    ./b2 \
        --user-config=user-config-wasm.jam \
        toolset=emscripten \
        variant=release \
        link=static \
        threading=single \
        runtime-link=static \
        --layout=system \
        --prefix="$AUX_PREFIX" \
        --without-context \
        --without-coroutine \
        --without-fiber \
        --without-thread \
        --without-stacktrace \
        -j8 \
        install
)
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
(
    mkdir -p "$AUX_BUILD/ecl-host"
    mkdir -p "$AUX_BUILD/ecl-wasm"
    
    if [[ ! -d "$EXTERN_DIR/ecl" ]]; then
        echo "Cloning ECL..."
        git clone https://gitlab.com/embeddable-common-lisp/ecl.git "$EXTERN_DIR/ecl"
    fi
    
    echo "Building native ECL (Host)..."
    cd "$AUX_BUILD/ecl-host"
    if [[ ! -f Makefile ]]; then
        "$EXTERN_DIR/ecl/configure" \
            --prefix="$AUX_BUILD/ecl-host/install" \
            --disable-shared
    fi
    make -j8
    make install
    
    export ECL_TO_RUN="$AUX_BUILD/ecl-host/install/bin/ecl"
    
    echo "Building WebAssembly ECL..."
    cd "$AUX_BUILD/ecl-wasm"
    
    BUILD_ARCH=$(cc -dumpmachine || echo "x86_64-pc-linux-gnu")
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/ecl/configure" \
            --host=wasm32-unknown-emscripten \
            --build="$BUILD_ARCH" \
            --with-cross-config="$EXTERN_DIR/ecl/src/util/wasm32-unknown-emscripten.cross_config" \
            --prefix="$AUX_PREFIX" \
            --disable-shared \
            --with-tcp=no \
            --with-cmp=no \
            CFLAGS="$CFLAGS" \
            CXXFLAGS="$CXXFLAGS" \
            LDFLAGS="$LDFLAGS"
    fi
    
    emmake make -j8
    emmake make install
)
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
# --- LIBOPENBLAS ---
(
    mkdir -p "$AUX_BUILD/openblas"
    cd "$AUX_BUILD/openblas"
    
    if [[ ! -d "$EXTERN_DIR/OpenBLAS" ]]; then
        echo "Cloning OpenBLAS..."
        git clone --depth 1 https://github.com/OpenMathLib/OpenBLAS.git "$EXTERN_DIR/OpenBLAS"
    fi
    
    cd "$EXTERN_DIR/OpenBLAS"
    
    if [[ ! -f libopenblas.a ]]; then
        emmake make -j8 \
            HOSTCC="cc" \
            TARGET="GENERIC" \
            NOFORTRAN=1 \
            USE_THREAD=0 \
            NO_SHARED=1 \
            MAKE_NB_JOBS=0
    fi
    
    emmake make PREFIX="$AUX_PREFIX" NOFORTRAN=1 NO_SHARED=1 install
)
# --- LIBFFLAS_FFPACK ---
(
    mkdir -p "$AUX_BUILD/fflas_ffpack"
    cd "$AUX_BUILD/fflas_ffpack"
    
    if [[ ! -d "$EXTERN_DIR/fflas-ffpack" ]]; then
        echo "Cloning FFLAS-FFPACK..."
        git clone https://github.com/linbox-team/fflas-ffpack.git "$EXTERN_DIR/fflas-ffpack"
        
        cd "$EXTERN_DIR/fflas-ffpack"
        if [[ ! -f configure ]]; then
            if [[ -f autogen.sh ]]; then
                ./autogen.sh
            else
                autoreconf -vfi
            fi
        fi
        cd -
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/fflas-ffpack/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --prefix="$AUX_PREFIX" \
            --disable-shared \
            --disable-openmp \
            --with-gmp="$AUX_PREFIX" \
            --with-givaro="$AUX_PREFIX" \
            --with-blas-libs="-L$AUX_PREFIX/lib -lopenblas" \
            CFLAGS="$CFLAGS" \
            CXXFLAGS="$CXXFLAGS -std=c++11" \
            LDFLAGS="$LDFLAGS"
    fi
    
    emmake make -j8
    emmake make install
)
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
(
    mkdir -p "$AUX_BUILD/gap"
    cd "$AUX_BUILD/gap"
    
    if [[ ! -d "$EXTERN_DIR/gap" ]]; then
        echo "Cloning GAP..."
        git clone https://github.com/gap-system/gap.git "$EXTERN_DIR/gap"
        
        cd "$EXTERN_DIR/gap"
        if [[ ! -f configure ]]; then
            ./autogen.sh
        fi
        cd -
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/gap/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --prefix="$AUX_PREFIX" \
            --disable-shared \
            --with-gmp="$AUX_PREFIX" \
            --with-readline="$AUX_PREFIX" \
            --with-zlib="$AUX_PREFIX" \
            CFLAGS="$CFLAGS" \
            CXXFLAGS="$CXXFLAGS" \
            LDFLAGS="$LDFLAGS"
    fi
    
    emmake make -j8 libgap.la
    emmake make install-libgap install-headers
)
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
# --- LIBLFUNCTION ---
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
(
    mkdir -p "$AUX_BUILD/mpc"
    cd "$AUX_BUILD/mpc"
    
    if [[ ! -d "$EXTERN_DIR/mpc-1.4.1" ]]; then
        echo "Downloading MPC..."
        curl -sSL https://ftp.gnu.org/gnu/mpc/mpc-1.4.1.tar.xz | tar xJ -C "$EXTERN_DIR"
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/mpc-1.4.1/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --with-gmp="$AUX_PREFIX" \
            --with-mpfr="$AUX_PREFIX" \
            --disable-shared \
            --prefix="$AUX_PREFIX" \
            CFLAGS="$CFLAGS" \
            CXXFLAGS="$CXXFLAGS" \
            LDFLAGS="$LDFLAGS"
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBMPFI ---
(
    mkdir -p "$AUX_BUILD/mpfi"
    cd "$AUX_BUILD/mpfi"
    
    if [[ ! -d "$EXTERN_DIR/mpfi" ]]; then
        echo "Cloning mpfi..."
        git clone https://gitlab.inria.fr/mpfi/mpfi.git "$EXTERN_DIR/mpfi"
        
        cd "$EXTERN_DIR/mpfi"
        if [[ ! -f configure ]]; then
            autoreconf -vfi
        fi
        cd -
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/mpfi/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --with-gmp="$AUX_PREFIX" \
            --with-mpfr="$AUX_PREFIX" \
            --disable-shared \
            --prefix="$AUX_PREFIX" \
            CFLAGS="$CFLAGS" \
            CXXFLAGS="$CXXFLAGS" \
            LDFLAGS="$LDFLAGS"
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBNAUTY ---
(
    mkdir -p "$AUX_BUILD/nauty"
    cd "$AUX_BUILD/nauty"
    
    if [[ ! -d "$EXTERN_DIR/nauty2_9_3" ]]; then
        echo "Downloading nauty..."
        curl -sSL https://pallini.di.uniroma1.it/nauty2_9_3.tar.gz | tar xz -C "$EXTERN_DIR"
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/nauty2_9_3/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --prefix="$AUX_PREFIX" \
            CFLAGS="$CFLAGS" \
            CXXFLAGS="$CXXFLAGS" \
            LDFLAGS="$LDFLAGS"
    fi
    
    emmake make nauty.a -j8
    
    echo "Installing nauty manually..."
    mkdir -p "$AUX_PREFIX/include/nauty" "$AUX_PREFIX/lib"
    
    cp "$EXTERN_DIR/nauty2_9_3/"*.h "$AUX_PREFIX/include/nauty/"
    
    cp nauty.a "$AUX_PREFIX/lib/libnauty.a"
    
    emranlib "$AUX_PREFIX/lib/libnauty.a"
)
# --- LIBNCURSES ---
(
    mkdir -p "$AUX_BUILD/ncurses"
    cd "$AUX_BUILD/ncurses"
    
    if [[ ! -d "$EXTERN_DIR/ncurses" ]]; then
        echo "Downloading ncurses..."
        mkdir -p "$EXTERN_DIR/ncurses_temp"
        curl -sSL https://invisible-island.net/datafiles/release/ncurses.tar.gz | tar xz -C "$EXTERN_DIR/ncurses_temp"
        
        SRC_DIR=$(find "$EXTERN_DIR/ncurses_temp" -mindepth 1 -maxdepth 1 -type d | head -n 1)
        mv "$SRC_DIR" "$EXTERN_DIR/ncurses"
        rm -rf "$EXTERN_DIR/ncurses_temp"
    fi
    
    cd "$EXTERN_DIR/ncurses"
    
    if [[ ! -f Makefile ]]; then
        emconfigure ./configure \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --prefix="$AUX_PREFIX" \
            --without-shared \
            --without-cxx \
            --without-ada \
            --without-progs \
            --without-tests \
            --enable-static \
            CFLAGS="$CFLAGS" \
            CXXFLAGS="$CXXFLAGS" \
            LDFLAGS="$LDFLAGS"
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBOPENSSL ---
(
    mkdir -p "$AUX_BUILD/openssl"
    cd "$AUX_BUILD/openssl"
    
    if [[ ! -d "$EXTERN_DIR/openssl" ]]; then
        echo "Cloning openssl..."
        git clone --depth 1 https://github.com/openssl/openssl.git "$EXTERN_DIR/openssl"
    fi
    
    cd "$EXTERN_DIR/openssl"
    
    if [[ ! -f Makefile ]]; then
        emconfigure ./Configure linux-generic32 \
            --prefix="$AUX_PREFIX" \
            no-shared \
            no-asm \
            no-threads \
            no-dso \
            no-tests
    fi
    
    emmake make -j8
    emmake make install_sw
)
# --- LIBPARI ---
(
    mkdir -p "$AUX_BUILD/pari"
    cd "$AUX_BUILD/pari"
    
    if [[ ! -d "$EXTERN_DIR/pari-2.17.3" ]]; then
        echo "Downloading pari..."
        curl -sSL https://pari.math.u-bordeaux.fr/pub/pari/unix/pari-2.17.3.tar.gz | tar xz -C "$EXTERN_DIR"
    fi
    
    cd "$EXTERN_DIR/pari-2.17.3"
    
    if [[ ! -f Makefile ]]; then
        emconfigure ./Configure \
            --prefix="$AUX_PREFIX" \
            --with-gmp="$AUX_PREFIX" \
            --graphic=none
    fi
    
    emmake make lib-sta -j8
    
    emmake make install-lib-sta install-include
    
    emranlib "$AUX_PREFIX/lib/libpari.a"
)
# --- LIBPLANARITY ---
(
    mkdir -p "$AUX_BUILD/planarity"
    cd "$AUX_BUILD/planarity"
    
    if [[ ! -d "$EXTERN_DIR/planarity" ]]; then
        echo "Cloning planarity..."
        git clone https://github.com/graph-algorithms/edge-addition-planarity-suite.git "$EXTERN_DIR/planarity"
        
        cd "$EXTERN_DIR/planarity"
        if [[ ! -f configure ]]; then
            if [[ -f autogen.sh ]]; then
                ./autogen.sh
            else
                autoreconf -vfi
            fi
        fi
        cd -
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/planarity/configure" \
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
# --- LIBPPL ---
(
    mkdir -p "$AUX_BUILD/ppl"
    cd "$AUX_BUILD/ppl"
    
    if [[ ! -d "$EXTERN_DIR/ppl" ]]; then
        echo "Cloning PPL..."
        git clone https://github.com/BUGSENG/PPL.git "$EXTERN_DIR/ppl"
        
        cd "$EXTERN_DIR/ppl"
        if [[ ! -f configure ]]; then
            autoreconf -vfi
        fi
        cd -
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/ppl/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --with-gmp-prefix="$AUX_PREFIX" \
            --enable-interfaces="c,cxx" \
            --disable-watchdog \
            --disable-shared \
            --prefix="$AUX_PREFIX" \
            CFLAGS="$CFLAGS" \
            CXXFLAGS="$CXXFLAGS" \
            LDFLAGS="$LDFLAGS"
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBPRIMECOUNT ---
(
    mkdir -p "$AUX_BUILD/primecount"
    cd "$AUX_BUILD/primecount"
    
    if [[ ! -d "$EXTERN_DIR/primecount" ]]; then
        echo "Cloning primecount..."
        git clone https://github.com/kimwalisch/primecount.git "$EXTERN_DIR/primecount"
    fi
    
    cd "$EXTERN_DIR/primecount"
    
    if [[ ! -f Makefile ]]; then
        emcmake cmake . \
            -DCMAKE_INSTALL_PREFIX="$AUX_PREFIX" \
            -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
            -DBUILD_SHARED_LIBS=OFF \
            -DBUILD_TESTS=OFF
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBPRIMESIEVE ---
(
    mkdir -p "$AUX_BUILD/primesieve"
    cd "$AUX_BUILD/primesieve"
    
    if [[ ! -d "$EXTERN_DIR/primesieve" ]]; then
        echo "Cloning primesieve..."
        git clone https://github.com/kimwalisch/primesieve.git "$EXTERN_DIR/primesieve"
    fi
    
    cd "$EXTERN_DIR/primesieve"
    
    if [[ ! -f Makefile ]]; then
        emcmake cmake . \
            -DCMAKE_INSTALL_PREFIX="$AUX_PREFIX" \
            -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
            -DBUILD_SHARED_LIBS=OFF \
            -DBUILD_STATIC_LIBS=ON \
            -DBUILD_TESTS=OFF
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBPYTHON3 ---
(
    PYTHON_VERSION="3.12.4"
    mkdir -p "$AUX_BUILD/python3"
    cd "$AUX_BUILD/python3"
    
    if [[ ! -d "$EXTERN_DIR/Python-$PYTHON_VERSION" ]]; then
        echo "Downloading Python $PYTHON_VERSION..."
        curl -sSL "https://www.python.org/ftp/python/$PYTHON_VERSION/Python-$PYTHON_VERSION.tgz" | tar xz -C "$EXTERN_DIR"
    fi
    
    cd "$EXTERN_DIR/Python-$PYTHON_VERSION"
    
    if [[ ! -f Makefile ]]; then
        export ac_cv_buggy_getaddrinfo=no
        export ac_cv_file__dev_ptmx=no
        export ac_cv_file__dev_ptc=no
        
        emconfigure ./configure \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --prefix="$AUX_PREFIX" \
            --disable-shared \
            --without-pymalloc \
            --disable-ipv6 \
            --without-ensurepip \
            --with-build-python=$(which python3.12) \
            CFLAGS="$CFLAGS" \
            CXXFLAGS="$CXXFLAGS" \
            LDFLAGS="$LDFLAGS"
    fi
    
    emmake make -j8 || emmake make
    emmake make install
)
# --- LIBQHULL ---
(
    mkdir -p "$AUX_BUILD/qhull"
    cd "$AUX_BUILD/qhull"
    
    if [[ ! -d "$EXTERN_DIR/qhull" ]]; then
        echo "Cloning qhull..."
        git clone https://github.com/qhull/qhull.git "$EXTERN_DIR/qhull"
    fi
    
    cd "$EXTERN_DIR/qhull"
    
    if [[ ! -f Makefile ]] && [[ ! -f CMakeCache.txt ]]; then
        emcmake cmake . \
            -DCMAKE_INSTALL_PREFIX="$AUX_PREFIX" \
            -DCMAKE_C_FLAGS="$CFLAGS" \
            -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
            -DBUILD_SHARED_LIBS=OFF
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBREADLINE ---
(
    mkdir -p "$AUX_BUILD/readline"
    cd "$AUX_BUILD/readline"
    
    if [[ ! -d "$EXTERN_DIR/readline" ]]; then
        echo "Cloning readline..."
        git clone https://git.savannah.gnu.org/git/readline.git "$EXTERN_DIR/readline"
        
        cd "$EXTERN_DIR/readline"
        if [[ ! -f configure ]]; then
            autoreconf -vfi || autoconf
        fi
        cd -
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/readline/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --prefix="$AUX_PREFIX" \
            --disable-shared \
            --enable-static \
            --with-curses \
            CFLAGS="$CFLAGS" \
            LDFLAGS="$LDFLAGS"
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBRW ---
(
    mkdir -p "$AUX_BUILD/rw"
    cd "$AUX_BUILD/rw"
    
    if [[ ! -d "$EXTERN_DIR/rw-0.10" ]]; then
        echo "Downloading rw (librw)..."
        curl -sSL "https://sourceforge.net/projects/rankwidth/files/rw-0.10.tar.gz/download" | tar xz -C "$EXTERN_DIR"
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/rw-0.10/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --prefix="$AUX_PREFIX" \
            --disable-shared \
            --disable-executable \
            CFLAGS="$CFLAGS" \
            LDFLAGS="$LDFLAGS"
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBSINGULAR ---
(
    mkdir -p "$AUX_BUILD/singular"
    cd "$AUX_BUILD/singular"
    
    if [[ ! -d "$EXTERN_DIR/singular" ]]; then
        echo "Cloning Singular..."
        git clone https://github.com/Singular/Singular.git "$EXTERN_DIR/singular"
        
        cd "$EXTERN_DIR/singular"
        if [[ ! -f configure ]]; then
            ./autogen.sh
        fi
        cd -
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/singular/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --prefix="$AUX_PREFIX" \
            --disable-shared \
            --enable-static \
            --with-gmp="$AUX_PREFIX" \
            --with-readline="$AUX_PREFIX" \
            --without-python \
            --disable-doc \
            --disable-polymake \
            --without-dynamic \
            CFLAGS="$CFLAGS" \
            CXXFLAGS="$CXXFLAGS -std=c++11" \
            LDFLAGS="$LDFLAGS"
    fi
    
    emmake make -j8 -k || true
    
    emmake make install-libLTLIBRARIES install-includeHEADERS -k || true
    emmake make install-nodist_includeHEADERS -k || true
)
# --- LIBSQLITE3 ---
(
    mkdir -p "$AUX_BUILD/sqlite3"
    
    if [[ ! -d "$EXTERN_DIR/sqlite3" ]]; then
        echo "Cloning SQLite via Fossil..."
        mkdir -p "$EXTERN_DIR/sqlite3"
        cd "$EXTERN_DIR/sqlite3"
        
        fossil open https://sqlite.org/src
    fi
    
    cd "$AUX_BUILD/sqlite3"
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/sqlite3/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --prefix="$AUX_PREFIX" \
            --disable-shared \
            --enable-static \
            --disable-readline \
            --disable-dynamic-extensions \
            CFLAGS="$CFLAGS -DSQLITE_OMIT_LOAD_EXTENSION" \
            LDFLAGS="$LDFLAGS"
    fi
    
    emmake make -j8 libsqlite3.la
    
    emmake make install-libLTLIBRARIES install-includeHEADERS
)
# --- LIBSUITESPARSE ---
(
    mkdir -p "$AUX_BUILD/suitesparse"
    cd "$AUX_BUILD/suitesparse"
    
    if [[ ! -d "$EXTERN_DIR/suitesparse" ]]; then
        echo "Cloning SuiteSparse..."
        git clone --depth 1 https://github.com/DrTimothyAldenDavis/SuiteSparse.git "$EXTERN_DIR/suitesparse"
    fi
    
    cd "$EXTERN_DIR/suitesparse"
    
    if [[ ! -f Makefile ]] && [[ ! -f CMakeCache.txt ]]; then
        emcmake cmake . \
            -DCMAKE_INSTALL_PREFIX="$AUX_PREFIX" \
            -DCMAKE_C_FLAGS="$CFLAGS" \
            -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
            -DBUILD_SHARED_LIBS=OFF \
            -DSUITESPARSE_ENABLE_PROJECTS="amd;camd;colamd;ccolamd;cholmod;cxsparse;umfpack;spqr" \
            -DNFORTRAN=ON
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBSYMMETRICA ---
(
    mkdir -p "$AUX_BUILD/symmetrica"
    cd "$AUX_BUILD/symmetrica"
    
    if [[ ! -d "$EXTERN_DIR/symmetrica" ]]; then
        echo "Cloning symmetrica..."
        git clone https://gitlab.com/sagemath/symmetrica.git "$EXTERN_DIR/symmetrica"
        
        cd "$EXTERN_DIR/symmetrica"
        if [[ ! -f configure ]]; then
            autoreconf -i
        fi
        cd -
    fi
    
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/symmetrica/configure" \
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
# --- LIBZ ---
(
    mkdir -p "$AUX_BUILD/zlib"
    cd "$AUX_BUILD/zlib"
    
    if [[ ! -d "$EXTERN_DIR/zlib" ]]; then
        echo "Cloning zlib..."
        git clone https://github.com/madler/zlib.git "$EXTERN_DIR/zlib"
    fi
    
    cd "$EXTERN_DIR/zlib"
    
    if [[ ! -f configure.log ]]; then
        emconfigure ./configure \
            --prefix="$AUX_PREFIX" \
            --static
    fi
    
    emmake make -j8
    emmake make install
)
# --- LIBZMQ ---
(
    mkdir -p "$AUX_BUILD/zmq"
    cd "$AUX_BUILD/zmq"
    
    if [[ ! -d "$EXTERN_DIR/libzmq" ]]; then
        echo "Cloning libzmq..."
        git clone https://github.com/zeromq/libzmq.git "$EXTERN_DIR/libzmq"
    fi
    
    cd "$EXTERN_DIR/libzmq"
    
    if [[ ! -f Makefile ]] && [[ ! -f CMakeCache.txt ]]; then
        emcmake cmake . \
            -DCMAKE_INSTALL_PREFIX="$AUX_PREFIX" \
            -DCMAKE_C_FLAGS="$CFLAGS" \
            -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
            -DBUILD_SHARED_LIBS=OFF \
            -DBUILD_STATIC=ON \
            -DZMQ_BUILD_TESTS=OFF \
            -DWITH_PERF_TOOL=OFF \
            -DENABLE_CPACK=OFF
    fi
    
    emmake make -j8
    emmake make install
)

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
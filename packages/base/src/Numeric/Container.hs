{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE UndecidableInstances #-}

-----------------------------------------------------------------------------
-- |
-- Module      :  Numeric.Container
-- Copyright   :  (c) Alberto Ruiz 2010-14
-- License     :  BSD3
-- Maintainer  :  Alberto Ruiz
-- Stability   :  provisional
--
-- Basic numeric operations on 'Vector' and 'Matrix', including conversion routines.
--
-- The 'Container' class is used to define optimized generic functions which work
-- on 'Vector' and 'Matrix' with real or complex elements.
--
-- Some of these functions are also available in the instances of the standard
-- numeric Haskell classes provided by "Numeric.LinearAlgebra".
--
-----------------------------------------------------------------------------
{-# OPTIONS_HADDOCK hide #-}

module Numeric.Container (
    -- * Basic functions
    module Data.Packed,
    konst, build,
    linspace,
    diag, ident,
    ctrans,
    -- * Generic operations
    Container,
    add, mul, sub, divide, equal, scaleRecip, addConstant,
    scalar, conj, scale, arctan2, cmap,
    atIndex, minIndex, maxIndex, minElement, maxElement,
    sumElements, prodElements,
    step, cond, find, assoc, accum,
    Transposable(..), Linear(..),
    -- * Matrix product
    Product(..), udot, dot, (◇),
    Mul(..),
    Contraction(..),(<.>),
    optimiseMult,
    mXm,mXv,vXm,LSDiv(..),
    outer, kronecker,
    -- * Random numbers
    RandDist(..),
    randomVector,
    gaussianSample,
    uniformSample,
    -- * Element conversion
    Convert(..),
    Complexable(),
    RealElement(),

    RealOf, ComplexOf, SingleOf, DoubleOf,

    IndexOf,
    module Data.Complex,
    -- * IO
    module Data.Packed.IO,
    -- * Misc
    Testable(..)
) where

import Data.Packed hiding (stepD, stepF, condD, condF, conjugateC, conjugateQ)
import Data.Packed.Internal.Numeric
import Data.Complex
import Numeric.LinearAlgebra.Algorithms(Field,linearSolveSVD)
import Data.Monoid(Monoid(mconcat))
import Data.Packed.IO
import Numeric.LinearAlgebra.Random

------------------------------------------------------------------

{- | Creates a real vector containing a range of values:

>>> linspace 5 (-3,7::Double)
fromList [-3.0,-0.5,2.0,4.5,7.0]@

>>> linspace 5 (8,2+i) :: Vector (Complex Double)
fromList [8.0 :+ 0.0,6.5 :+ 0.25,5.0 :+ 0.5,3.5 :+ 0.75,2.0 :+ 1.0]

Logarithmic spacing can be defined as follows:

@logspace n (a,b) = 10 ** linspace n (a,b)@
-}
linspace :: (Container Vector e) => Int -> (e, e) -> Vector e
linspace 0 (a,b) = fromList[(a+b)/2]
linspace n (a,b) = addConstant a $ scale s $ fromList $ map fromIntegral [0 .. n-1]
    where s = (b-a)/fromIntegral (n-1)

--------------------------------------------------------

{- | Matrix product, matrix - vector product, and dot product (equivalent to 'contraction')

(This operator can also be written using the unicode symbol ◇ (25c7).)

Examples:

>>> let a = (3><4)   [1..]      :: Matrix Double
>>> let v = fromList [1,0,2,-1] :: Vector Double
>>> let u = fromList [1,2,3]    :: Vector Double

>>> a
(3><4)
 [ 1.0,  2.0,  3.0,  4.0
 , 5.0,  6.0,  7.0,  8.0
 , 9.0, 10.0, 11.0, 12.0 ]

matrix × matrix:

>>> disp 2 (a <.> trans a)
3x3
 30   70  110
 70  174  278
110  278  446

matrix × vector:

>>> a <.> v
fromList [3.0,11.0,19.0]

dot product:

>>> u <.> fromList[3,2,1::Double]
10

For complex vectors the first argument is conjugated:

>>> fromList [1,i] <.> fromList[2*i+1,3]
1.0 :+ (-1.0)

>>> fromList [1,i,1-i] <.> complex a
fromList [10.0 :+ 4.0,12.0 :+ 4.0,14.0 :+ 4.0,16.0 :+ 4.0]
-}
infixl 7 <.>
(<.>) :: Contraction a b c => a -> b -> c
(<.>) = contraction


class Contraction a b c | a b -> c
  where
    -- | Matrix product, matrix - vector product, and dot product
    contraction :: a -> b -> c

instance (Product t, Container Vector t) => Contraction (Vector t) (Vector t) t where
    u `contraction` v = conj u `udot` v

instance Product t => Contraction (Matrix t) (Vector t) (Vector t) where
    contraction = mXv

instance (Container Vector t, Product t) => Contraction (Vector t) (Matrix t) (Vector t) where
    contraction v m = (conj v) `vXm` m

instance Product t => Contraction (Matrix t) (Matrix t) (Matrix t) where
    contraction = mXm


--------------------------------------------------------------------------------

class Mul a b c | a b -> c where
 infixl 7 <>
 -- | Matrix-matrix, matrix-vector, and vector-matrix products.
 (<>)  :: Product t => a t -> b t -> c t

instance Mul Matrix Matrix Matrix where
    (<>) = mXm

instance Mul Matrix Vector Vector where
    (<>) m v = flatten $ m <> asColumn v

instance Mul Vector Matrix Vector where
    (<>) v m = flatten $ asRow v <> m

--------------------------------------------------------------------------------

class LSDiv c where
 infixl 7 <\>
 -- | least squares solution of a linear system, similar to the \\ operator of Matlab\/Octave (based on linearSolveSVD)
 (<\>)  :: Field t => Matrix t -> c t -> c t

instance LSDiv Vector where
    m <\> v = flatten (linearSolveSVD m (reshape 1 v))

instance LSDiv Matrix where
    (<\>) = linearSolveSVD

--------------------------------------------------------------------------------

class Konst e d c | d -> c, c -> d
  where
    -- |
    -- >>> konst 7 3 :: Vector Float
    -- fromList [7.0,7.0,7.0]
    --
    -- >>> konst i (3::Int,4::Int)
    -- (3><4)
    --  [ 0.0 :+ 1.0, 0.0 :+ 1.0, 0.0 :+ 1.0, 0.0 :+ 1.0
    --  , 0.0 :+ 1.0, 0.0 :+ 1.0, 0.0 :+ 1.0, 0.0 :+ 1.0
    --  , 0.0 :+ 1.0, 0.0 :+ 1.0, 0.0 :+ 1.0, 0.0 :+ 1.0 ]
    --
    konst :: e -> d -> c e

instance Container Vector e => Konst e Int Vector
  where
    konst = konst'

instance Container Vector e => Konst e (Int,Int) Matrix
  where
    konst = konst'

--------------------------------------------------------------------------------

class Build d f c e | d -> c, c -> d, f -> e, f -> d, f -> c, c e -> f, d e -> f
  where
    -- |
    -- >>> build 5 (**2) :: Vector Double
    -- fromList [0.0,1.0,4.0,9.0,16.0]
    --
    -- Hilbert matrix of order N:
    --
    -- >>> let hilb n = build (n,n) (\i j -> 1/(i+j+1)) :: Matrix Double
    -- >>> putStr . dispf 2 $ hilb 3
    -- 3x3
    -- 1.00  0.50  0.33
    -- 0.50  0.33  0.25
    -- 0.33  0.25  0.20
    --
    build :: d -> f -> c e

instance Container Vector e => Build Int (e -> e) Vector e
  where
    build = build'

instance Container Matrix e => Build (Int,Int) (e -> e -> e) Matrix e
  where
    build = build'

--------------------------------------------------------------------------------

-- | alternative unicode symbol (25c7) for 'contraction'
(◇) :: Contraction a b c => a -> b -> c
infixl 7 ◇
(◇) = contraction

-- | dot product: @cdot u v = 'udot' ('conj' u) v@
dot :: (Container Vector t, Product t) => Vector t -> Vector t -> t
dot u v = udot (conj u) v

--------------------------------------------------------------------------------

optimiseMult :: Monoid (Matrix t) => [Matrix t] -> Matrix t
optimiseMult = mconcat

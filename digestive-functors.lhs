Digestive Functors
==================

Introduction
------------

> {-# LANGUAGE OverloadedStrings #-}
> import Text.Digestive.Types
> import Text.Digestive.Validator
> import Text.Digestive.Blaze.Html5
> import Text.Blaze.Renderer.Pretty (renderHtml)
> import Text.Blaze (Html)
> import Data.Monoid (mempty, mappend)
> import Control.Monad.State
> import Control.Applicative

Digestive Functors is a Haskell framework/library that provides a general way to
create forms, based on *idioms*, or *applicative functors*. It is an improvement
of the original formlets[^formlets] in a number of ways.

[^formlets]: By formlets, we mean the Haskell `formlets` library by Chris
    Eidhof, based on [http://groups.inf.ed.ac.uk/links/formlets/]().

TODO: Insert references to chris's formlets package, and the original paper

It differs from the original *formlets* package in a number of ways. Important
benefits of our work is that:

- Instead of just producing errors, the errors have a reference to the original
  input field (or composition of input fields) where they originate from. This
  allows us to show the relevant errors directly next to the input field, which
  is desirable from a GUI-perspective.

- We aim to provide functions with which the resulting "view" can be easily
  changed. This way, the developer using the library can refer to certain input
  fields, which allows him to refer to these fields in, for example, additional
  JavaScript code.

- While HTML forms remains the main focus, we do not want to be limited to it.
  Another backend could, for example, provide a command-line input prompt.

A note on terminology: with "input field", we mean a **single** input field,
the visual representation of a single HTML `<input>` element. With "form" we
mean a composition of input fields -- possibly, this is a single field, but
usually, a form will be composed of multiple fields.

Applicative functors
--------------------

This section explains how applicative functors are used in the library, and we
explain why applicative functors are an excellent way to represent HTML forms.
If you are familiar with the old formlets package, you can skip this section.

Applicative funtors usually map very well onto Haskell datatype constructors.
Given the following type, which represents the name and age of a user:

> data User = User String Integer
>           deriving (Show)

We have a function which returns serializable values from a key-value store such
as [redis]:

> storeGet :: Read a => String -> IO a
> storeGet key = fail "Not implemented"

We can now use the fact that `IO` is an applicative functor to create a function
which constructs a `User` in `IO`:

> getUser :: IO User
> getUser = User <$> storeGet "user_name"
>                <*> storeGet "user_age"

We can conclude that using applicative functors to construct values result in
very readable and concise code.

The `getUser` example used above is very similar to the way we would use HTML
forms -- because it's an applicative functor, too.

> userForm :: (Monad m, Functor m) => Form m String String Html User
> userForm = User <$> inputText Nothing
>                 <*> inputTextRead "No read" (Just 20)

Don't let the complicated type of `userForm` scare you: it's just a `Form`
returning a `User` -- we will see the details later. We give no default value
(`Nothing`) to the username field, and 20 (`Just 20`) as default value to the
age field.

Composing forms
---------------

The advantage of using applicative functors to create forms over classical
approaches is composability. For example, if we want to create a form in which
you can enter a couple, we can easily reuse our `userForm`.

> data Couple = Couple User User
>             deriving (Show)

> coupleForm :: (Monad m, Functor m) => Form m String String Html Couple
> coupleForm = Couple <$> userForm
>                     <*> userForm

Validation
----------

In Belgium, people can only marry once they have reached the age of 18 -- and
our clients wants us to integrate this into our web application. This is a
simple example of validation.

> isAdult :: Monad m => Validator m String User
> isAdult = check "Not an adult!" $ \(User _ age) -> age >= 18

Once we have constructed this `Validator`, we can integrate it with our form:

> coupleForm' :: (Monad m, Functor m) => Form m String String Html Couple
> coupleForm' = Couple <$> userForm `validate` [isAdult]
>                      <*> userForm `validate` [isAdult]

Note that we insert this validator in the couple form, not in the user form --
we allow users under 18, they just cannot belong to a couple.

Suppose an end user fills in the form. However, he tries to register a 16-year
old user in a couple. The validation does not allow this, so we will receive the
"Not an adult!" error.

However, the end user filled in two users. If only one of them is underage, we
want to show the error next to the form of the underage user, not next to the
form of the valid user. How can we do this?

Tracing errors
--------------

There is always some sort of ID associated with every input field. This is a
prerequisite of any form library -- our server will receive something like:

    POST / HTTP/1.1
    Content-Length: 23
    Content-Type: application/x-www-form-urlencoded
    
    field1=jasper&field2=20

If we had no ID associated with the input fields, we cannot construct a `User`,
since we do not know if "jasper" is the username or the age.

This allows us to do basic error tracing: if we associate an ID with the error,
we can trace it back to the corresponding input field. While this allows us to
do error tracing on *input fields*, it does not allow us to do error tracing on
*forms*. Forms, by default, have no ID -- they are a composition of input
fields. How can we represent this in our `Form` type?

Composing forms in State
------------------------

TODO: Clarify that this section is about the *original* paper

We first examine how the ID's are constructed in the applicative functor. The
idea is very simple. Our `Couple` form could be represented visually using a
simple tree structure:

    Couple
    |- User
    |  |- Name
    |  |- Age
    |- User
    |  |- Name
    |  |- Age

The requirements of the algorithm generating the ID's are very simple:

- every leaf requires a different ID;
- the ID's do not have to be in a partical order, however;
- it has to be deterministic.

Such an algoritm is easily written in the state monad. The `Form` type makes use
of this by incorporating a state monad. When we want a different ID for every
leaf, we basically want that when we use `a <*> b`, `a` will be assigned a
different ID than `b`.

This can be done by modifying our state in the `<*>` operator (we use `ap'`
here, which is a simplified version for illustration purposes):

> ap1 :: State Int (a -> b) -> State Int a -> State Int b
> ap1 s1 s2 = do
>     f <- s1
>     modify (+ 1)
>     x <- s2
>     return $ f x

This will generate the following tree (supposing the initial state is 0):

    Couple
    |- User
    |  |- Name (0)
    |  |- Age  (1)
    |- User
    |  |- Name (2)
    |  |- Age  (3)

This approach allows us to take the ID's from the data we get from the browser,
and create a `Couple`. It also allows us to trace down *some* errors to specific
fields: only the errors that generate from input fields.

But we want to take this further. We don't want to validate only input fields,
we want to validate forms. Say you have a simple form consisting of two dates:
an arrival and a departure date. The departure date cannot be before the arrival
date, this is a validation rule. But this is an error which cannot be traced
down to either of the fields -- the error orginated from the composition of the
two fields.

Changing forms
--------------

In the original implementation, one could add labels and other custom HTML
elements to the form using applicative.

> userForm1 :: (Monad m, Functor m) => Form m String String Html User
> userForm1 = User <$> (view "Name: " *> inputText Nothing)
>                  <*> (view "Age: "  *> inputTextRead "No read" (Just 20))

However, there is an important downside to this approach. When making HTML
forms, it is desirable to use semantic `<label>` tags, linking the label to the
form using a `for` attribute [^for-attribute]. However, since the `view` part
and the `inputString` part are composed using `*>`, they will both have a
different ID -- this means we cannot refer to the input field generated by the
`inputString` function in the HTML generated by the `view` function.

[^for-attribute]: This allows the user to, for example, click the text instead
    of the (smaller) radio button, making the form more user-friendly.

The solution is quite straightforward: we want an "appending" of forms which
does *not* change the current ID. For this appending, we can implement the
Monoid typeclass, so that `mempty` represents an empty form, and `mappend` joins
two forms, retaining the ID.

This joining of forms is simply mappending the views. If we join multiple forms
which all return a result, only the first one will be taken into account (since
we only have one ID). Multiple results makes little sense from a programmer's
perspective, but we have conform to the monoid laws.

> userForm2 :: (Monad m, Functor m) => Form m String String Html User
> userForm2 = User
>     <$> (view "Name: " `mappend` inputText Nothing)
>     <*> (view "Age: "  `mappend` inputTextRead "No read" (Just 20))

Now, `view` and `inputText` will have access to the same ID. We can use this
fact when we insert a label:

> userForm3 :: (Monad m, Functor m) => Form m String String Html User
> userForm3 = User
>     <$> (label "Name: " `mappend` inputText Nothing)
>     <*> (label "Age: "  `mappend` inputTextRead "No read" (Just 20))

We can see in the rendered form that the labels are indeed correct:

    <label for="f0">Name: </label>
    <input type="text" name="f0" id="f0" value="" />
    <label for="f1">Age: </label>
    <input type="text" name="f1" id="f1" value="20" />

Utility functions
-----------------

> testGetForm :: Form Maybe String String Html a
>             -> Maybe (Either String a)
> testGetForm form = eitherForm (mapView renderHtml form) mempty
> 
> testPostForm :: Form Maybe String String Html a
>              -> [(Integer, String)]
>              -> Maybe (Either String a)
> testPostForm form env = eitherForm (mapView renderHtml form) $ Environment $
>     \key -> return $ lookup (unFormId key) env

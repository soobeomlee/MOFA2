import scipy as s
import scipy.special as special
from .basic_distributions import Distribution

from biofam.core.utils import *

class Beta(Distribution):
    """
    Class to define Beta distributions

    Equations:
    p(x|a,b) = GammaF(a+b)/(GammaF(a)*GammaF(b)) * x**(a-1) * (1-x)**(b-1)
    log p(x|a,b) = log[GammaF(a+b)/(GammaF(a)*GammaF(b))] + (a-1)*x + (b-1)*(1-x)
    E[x] = a/(a+b)
    var[x] = a*b / ((a+b)**2 * (a+b+1))
    """
    def __init__(self, dim, a, b, E=None):
        Distribution.__init__(self, dim)

        # Initialise parameters
        a = s.ones(dim)*a
        b = s.ones(dim)*b
        self.params = { 'a':a, 'b':b }

        # Initialise expectations
        if E is None:
            self.updateExpectations()
        else:
            self.updateExpectations()
            print("The expectation of the Beta distribution is initialized consistently with the provided parameters (not with the provided expectation)")

        # Check that dimensionalities match
        self.CheckDimensionalities()

    def updateExpectations(self):
        a, b = self.params['a'], self.params['b']
        E = s.divide(a,a+b)
        lnE = special.digamma(a) - special.digamma(a+b)
        lnEInv = special.digamma(b) - special.digamma(a+b) # expectation of ln(1-X)
        lnEInv[s.isinf(lnEInv)] = -s.inf # there is a numerical error in lnEInv if E=1
        self.expectations = { 'E':E, 'lnE':lnE, 'lnEInv':lnEInv }

    def sample(self, n=1):
        a = self.params['a']
        b = self.params['b']
        return s.random.beta(a, b)
